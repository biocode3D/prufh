
Prufh is a minimal 32 bit Forth language with 16 bit addresses 
for the pruss coprocessors found on TI chips such as those used 
on the beaglebone black. More properly, it is a threaded language 
for the pruss using Forth words and conventions.


What is it

    It consists of a compiler, the forth system itself, and an 
    optional program for loading and communicating with the forth 
    code proper.  

    Prufh is not intended as a general purpose language. It only 
    supports those features that are useful for the pruss' intended 
    functions.



Why is it

    It is intended to provide an easier means of programing and 
    debugging programs for the pru subsystem.  It also may allow 
    writing larger programs than would be feasible when programming 
    directly in assembly language.

    It is Forth because of its ease of implementation.



Getting Started

    As supplied Prufh is set up to be compiled on the BeagleBone black 
    (although cross compiling would not be difficult).

    First the pruss drivers must be loaded.  This can be a very fraught 
    process and I can't help with this.  
    Just do not proceed until /sys/class/uio/uio0 exists.

    After downloading change to the directory with your copy of Prufh.

    Run make which should compile prufh_term for you.

    Next run:

        ./prufh.pl -a "../am335_pru_package/pru_sw/utils/pasm -V3L"

    (Substitute the location of your pru assembler. Or ommit the 
    assembler directive and manually run your assembler against 
    prufh.prg)
    This will compile the default "prufh.4th" file into prufh.bin 
    and prufh.dat files.

    Now run 
        sudo ./prufh_term 

    After some harmless chatter it should return:
        Reset: 0x01234567

    Now you can type in forth commands (one per line).  For example:
        4
        2+
        emit

    That should return:  
        Got: 0x00000006

    Congratulations. the rest is up to you.
    Just add your forth or assembly code to prufh.4th file.

    If you wish to use prufh_term in your own project, it can be 
    used as is via stdin and stdout, or you can ask it to use 
    specified io. Use ./prufh_term -h for instructions.



Helpful information

    There should be no surprises in the way Prufh works if you are 
    familiar with Forth.  If you aren't familiar with Forth, there are 
    a number of tutorials etc. online.

    The list of defined words may be found in the prufh.def file.  For 
    explaination of their meaning, refer to standard Forth documentation.

    A word must be defined called "main".  "main" is executed on starting 
    the pruss system or whenever it is reset.

    Prufh supports binary, octal, decimal, and hex numbers via the usual 
    conventions (perl, C/C++).

    ";CODE" does two things, it terminates an assembly laguage word with 
    a jump to next and it switches the compiler out of assembly mode.  
    It may be omitted to save space if the definition ends in a branch 
    statement AND the next intruction is :CODE

    Exit prufh_term with "bye".

    Use the customary -h option for more information on the use of prufh.pl or prufh_term



Differences from Forth

    It is a "headerless" forth, which means that, while it saves on 
    memory, new words cannot be added or modified at run time. 

    For speed and to conserve data memory, more words are written as 
    primitives than might be the case otherwise.

    It does not support the full suite of compile time words of a 
    true forth system.  

    There is no support for strings. 

    Stack comments are not supported.



Current Limitations

    In the assembly language, the pseudo-op MVIx instructions are 
    not handled.

    Assembly macros are not supported and generally won't work; 
    but there isn't much need for them in prufh.

    In keeping with its intended use as a HW controller, only unsigned 
    integers are recognized; no negative(!) or floating point numbers.

    In  n 0 do ,,, -loop counting down to zero will wrap if the index 
    never exactly equals 0.



How it works (some understanding of Forth is helpful here)

    A prufh program, with the extension .4th, consists of primitives 
    written in assembly language and forth colon definitions.  This 
    file is processed by a perl program, prufh.pl, which preprocess 
    the assembly language and compiles the forth code. The assembly 
    code is output as prufh.prg.  The forth code is found in prufh.dat.

    prufh.dat is intended to be loaded into the pru data memory.  
    At its simplest, prufh.dat consists of a series of 16-bit addresses 
    each of which is the address of a forth word. That address may 
    point to a primitive, written in assembly and located in program 
    memory, or to another address in data memory. These are 
    distinguished by the fact that the data memory address have their 
    high bit set.

    When a program is run, "next" steps through the address table 
    starting at the address of the word "main".  As each address is 
    read, if its high bit is clear, execution jumps to that address. 
    If the high bit is set, the current address is saved on the return 
    stack and "next" repeats its process at the new address.

    When execution reaches the end of a primitive, control jumps back 
    to the begining of "next" which then looks at the next address.  
    The end of a colon definition is marked by the primitive word 
    "exit".  "exit" retrieves the old address form the return stack 
    and sends control back to "next" which increments the old address, 
    etc. etc.

    This picture is complicated only a little by the fact that branching
    words, variables, constants, and literals also store information in 
    the dictionary interleaved with the addresses.

    The prufh_term program has a dictionary of known words and 
    translates them to their corresponding address before sending
    them to the pruss.  As supplied, the prufh.4th program accepts
    address or numbers and executes them or places them on the stack
    respectively.

    The pruss has a hardware multiply unit so multiplies are very fast.
    It has no divide, however, so it is implemented in software and
    consequently is quite slow.



Nonstandard words
    
    sleep   ( n -- ) wait for n * 10 nanoseconds

    ?command    ( -- flag ) is an incomming command ready?

    @command    ( -- cmd )  fetch incomming command

    ?read       ( -- flag ) has last output been acknowledged?

    echo        ( n -- n )  output top of stack

    .           ( n -- )  output top of stack

    exec        ( addr -- )  execute word whose address is on stack

    oblige      ( -- )  executes incomming request, if any

    *           ( n1, n2 -- high, low) 32 bit multiply with 64 bit result

    setgpio     ( n -- ) set pin #n high

    clrglpio    ( n -- ) set pin #n low



TODO
    Add HW configuration and interrupt words
    Support running both pru coprocessors at the same time.
    Add quiet mode to prufh_term.
    Permit stack comments.
    Allow include files 
    Multitasking ?

