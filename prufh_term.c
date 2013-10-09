/*
    prufh_term.c                                                        
                                                                        
 Copyright 2013 John C Silvia                                           
                                                                        
 This file is part of prufh.                                            
                                                                        
    prufh is free software: you can redistribute it and/or modify       
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or   
    (at your option) any later version.                                 
                                                                        
    prufh is distributed in the hope that it will be useful,            
    but WITHOUT ANY WARRANTY; without even the implied warranty of      
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the       
    GNU General Public License for more details.                        
                                                                        
    You should have received a copy of the GNU General Public License   
    along with prufh.  If not, see <http://www.gnu.org/licenses/>.      
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <search.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>

#include "prussdrv.h"
#include <pruss_intc_mapping.h>


#define BUFFSIZE    32

#define AM33XX
#define PRU_NUM 	0
#define PRU_PROG    "prufh.bin"
#define PRU_DEFS    "prufh.defs"
#define PRU_DATA    "prufh.dat"

#define TOPRU       0
#define TOPRU_F     1
#define FROMPRU     2
#define FROMPRU_F   3

#define CMD_FLAG    1
#define LIT_FLAG    2

#define RECEIVE_SLEEP   100  // usecs to wait between checking for pru output
#define EXEC_SLEEP      1    // secs to wait between attempts to send command
#define EXEC_LIMIT      60   // # of attempts before give up on sending command

static int setupIO(int argc, char** argv);
static int exec(uint32_t cmd_addr, uint32_t flag);
static void* receive(void* param);
static int pruInit(unsigned short pruNum);

static int quiet_mode = 0;

unsigned int inpipe=0;
unsigned int outpipe=1;

static void *pruSharedMem;
static volatile uint32_t *pruSharedMem_int;

static void *pruDataMem;
static uint16_t *pruDataMem_int;


int main(int argc, char *argv[]) {
    char        *word, *pEnd;
    int         word_count, i, nread;
    uint32_t    cmd_addr, flag;
    char        *gap = " \n";
    char        buff[BUFFSIZE];
    ENTRY       definition, *wp;
    pthread_t   receive_t;

    if (setupIO(argc, argv)) {
         return EXIT_FAILURE;
     }

    // open list of forth word addresses
    FILE *file = fopen(PRU_DEFS, "r");
    if (file == NULL) {
        fprintf(stderr, "Unable to open definitions file\n");
        return EXIT_FAILURE;
    }

    // get number of definitions from begining of file
    fgets (buff, BUFFSIZE, file );
    word_count = atoi(buff);

    // create hash for definition table
    hcreate(word_count);

    // fill hash with name-address pairs
    for (i=0; i<word_count;) {
        fgets(buff, BUFFSIZE, file);

        word = strtok(buff, gap);
        if (word != NULL) {
            definition.key = strdup(word);
            definition.data = (void*)strtol(strtok(NULL, gap), NULL, 0);

            wp = hsearch(definition, ENTER);

            if (wp == NULL) {
                fprintf(stderr, "Dictionary entry failed on \"%s\"\n", word);
                return EXIT_FAILURE;
            } else {
                if (!quiet_mode) 
                    printf("Saved %9.9s  as   %p\n", wp->key, wp->data); 
            }	    
            i++;
        }
    }
    fclose(file);

    if (pruInit(PRU_NUM) == EXIT_SUCCESS) { 

        // start seperate thread to handle forth output
        if (pthread_create(&receive_t, NULL, receive, (void*) &outpipe)) {
        }

        // main loop, relay input to pru
        for(;;) {
            nread = read(0, buff, BUFFSIZE);  // wait here for input on stdin
            if (nread > 1) {
                word = strtok(buff, gap);

                // exit program on "bye" command
                if (strncmp(word, "bye", 3) == 0) break;

                // find address of word corresponding to input
                definition.key = word;
                wp = hsearch(definition, FIND);

                if (wp == NULL) {
                    // if input not defined, see if it is a number
                    cmd_addr = strtoul(word, &pEnd, 0);
                    if (pEnd == word) {
                        fprintf(stderr, "Unknown word, \"%s\"\n", word);
                        continue;
                    } else {
                        // if a number was input, signal forth to push it
                        flag = LIT_FLAG;
                        if (!quiet_mode) 
                            printf("Pushing %d\n", cmd_addr);
                    }
                } else {
                    // signal that a command address is being sent
                    flag = CMD_FLAG;
                    // retrieve the address
                    cmd_addr = (uint16_t)(intptr_t)(wp->data);
                    if (!quiet_mode) 
                        printf("Executing %9.9s %x\n", word, cmd_addr);
                }

                // send message to pruss
                if (exec(cmd_addr, flag)) {
                    fprintf(stderr, "Unable to issue command, \"%s\"\n", word);
                }
            }
        }
    }
    hdestroy();

    pthread_cancel(receive_t);
    pthread_join(receive_t, NULL);

    /* shutdown pru */
    prussdrv_pru_disable(PRU_NUM);
    prussdrv_exit();

    if (outpipe != 1) {
        close(outpipe);
    }
    if (inpipe != 0) {
        close(inpipe);
    }

    return EXIT_SUCCESS;
}


// On the pru, execute the command that corresponds to passed address
// If still unable to exececute after one minute, fails.
int exec(uint32_t cmd_addr, uint32_t flag) {
    int         wait = 0;

    // wait for any previous command to be acknowledged 
    while (pruSharedMem_int[TOPRU_F] > 0) {
        if (wait++ == EXEC_LIMIT) {
            return EXIT_FAILURE;
        }
        sleep(EXEC_SLEEP); 
    }

    // write to pru memory
    pruSharedMem_int[TOPRU] = cmd_addr;
    pruSharedMem_int[TOPRU_F] = flag;

    return EXIT_SUCCESS;
}


// Relay output from pru to stdout
void* receive(void* param) {
    int*            val;
    int             ready;
    FILE*           output;

    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
    pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, NULL);

    val = (int*)param;  //stupid, but compiler unhappy without this
    output = (FILE*)*val;
    if ((int)output == 1) output = stdout;

    // loop looking for output from pruss
    for(;;){
        ready = pruSharedMem_int[FROMPRU_F];
        if (ready != 0x00) {
            // check for special signal from pruss indicating a (re)start
            if (ready == 0x89abcdef) {
                if (quiet_mode) {
                    fprintf(output, "reset\n");                    
                } else {
                    fprintf(output, "Reset: %#0.8x\n", pruSharedMem_int[FROMPRU]);
                }
            } else {
                if (quiet_mode) {
                    fprintf(output, "%#0.8x\n", pruSharedMem_int[FROMPRU]);
                } else {
                    fprintf(output, "Got: %#0.8x\n", pruSharedMem_int[FROMPRU]);
                }
            }
            // acknowledge message
            pruSharedMem_int[FROMPRU_F] = 0x00;
        }
        // don't use all our cpu cycles
        usleep(RECEIVE_SLEEP);
    }
   pthread_exit(NULL);
} 


// Redirect stdin and stdout if requested at startup
int setupIO(int argc, char *argv[]) {
    int i;

    for (i=1; i<argc; i++) {
        if (strcmp(argv[i], "-h") == 0) {
            printf("Usage: prufh_term [-q] [-i INPUT] [-o OUTPUT]\n");
            printf("Where INPUT and OUTPUT are stdin, stdout, or pipe names.\n");
            printf("If not present they default to stdin and stdout.\n");
            printf("-q turns on quiet mode that prints only pru output.\n\n");
            return EXIT_SUCCESS;
        }
        if (strcmp(argv[i], "-q") == 0) {
            quiet_mode = 1;
        }
        if (strcmp(argv[i], "-i") == 0) {
            if (strcmp(argv[i], "stdin") == 0) {
                inpipe = 0;
            } else {
                inpipe = open(argv[i+1], O_RDONLY);
            }
            i++;
        }
        if (strcmp(argv[i], "-o") == 0) {
            if (strcmp(argv[i], "stdout") == 0) {
                inpipe = 0;
            } else {
                outpipe = open(argv[i+1], O_WRONLY);
            }
            i++;
        }
    }
    return EXIT_SUCCESS;
}


// Initialize the pruss
int pruInit(unsigned short pruNum) {
    int         i,  n;

    tpruss_intc_initdata pruss_intc_initdata = PRUSS_INTC_INITDATA;

    prussdrv_init();

    // Open PRU Interrupt 
    if (prussdrv_open(PRU_EVTOUT_0) != 0) {
        fprintf(stderr, "prussdrv_open open failed\n");
        return EXIT_FAILURE;
    }
    // initialize the interrupt
    prussdrv_pruintc_init(&pruss_intc_initdata);

    // Set up shared memory area for arm--pru communication
    prussdrv_map_prumem(PRUSS0_SHARED_DATARAM, &pruSharedMem);

    pruSharedMem_int =  (uint32_t *)pruSharedMem;

    pruSharedMem_int[TOPRU] = 0x00;
    pruSharedMem_int[TOPRU_F] = 0x00;
    pruSharedMem_int[FROMPRU] = 0x00;
    pruSharedMem_int[FROMPRU_F] = 0x00;

    // Initialize pointer to PRU data memory
    if (pruNum == 0) {
      prussdrv_map_prumem (PRUSS0_PRU0_DATARAM, &pruDataMem);
    }
    else if (pruNum == 1) {
      prussdrv_map_prumem (PRUSS0_PRU1_DATARAM, &pruDataMem);
    }  
    pruDataMem_int = (uint16_t *)pruDataMem;

    // Load dictionary into data memory
    FILE *file = fopen(PRU_DATA, "r");
    if (file == NULL) {
        fprintf(stderr, "Unable to open dictionary file\n");
        return EXIT_FAILURE;
    }

    i = 0;
    while (fscanf(file, "%x", &n) == 1) {
        pruDataMem_int[i++] = (uint16_t)n; 
    }
    fclose(file);

    // start pru program
    prussdrv_exec_program (PRU_NUM, PRU_PROG);

    return EXIT_SUCCESS;
}

        
