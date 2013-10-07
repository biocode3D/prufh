//    prufh.4th                                                        
//                                                                        
// Copyright 1999 John C Silvia                                           
//
// This file is part of prufh.
//
//    prufh is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    prufh is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with prufh.  If not, see <http://www.gnu.org/licenses/>.
//

// REGISTERS:
// tos -- top of stack
// psp -- parameter stack pointer
// rsp -- return stack pointer
// ip  -- instruction pointer
// w   -- working register used for address manipulation
// x   -- scratch register
// y   -- second scratch register (must be adjacent to x)
// z   -- third scratch register 
// limit -- inner do loop limit
// index -- inner do loop index
// incr  -- do loop increment value
// R25 to R29 -- used for hw multiply

.origin 0
.entrypoint STARTING_POINT

#define data_address_flag   15

#define shared_ram  c28
#define emit_avail  12
#define emit_value  8
#define cmd_avail   4
#define cmd_value   0

STARTING_POINT:
    jmp     INITIALIZATION

// forth "inner interpreter" called "next"
// (headerless word at known location)
    add	    $ip, $ip, 2
NEXT:
    lbbo    $w, $ip, 0, 2
    qbbs    DOCOLON, $w, data_address_flag
    jmp	    $w
DOCOLON:
    sub     $rsp, $rsp, 2
    sbbo    $ip, $rsp, 0, 2
    clr     $ip, $w, data_address_flag
    jmp     NEXT

INITIALIZATION:
    // clear STANDBY_INIT bit in SYSCFG to allow mem & pin access 
    lbco    R0, C4, 4, 4
    clr     R0, R0, 4
    sbco    R0, C4, 4, 4
    // init shared memory address in C28
    ldi     R0, 0x0100
    ldi     R1.w2, 0x0002
    ldi     R1.w0, 0x2028
    sbbo    R0, R1, 0, 4
    ldi     R0, 0x0000
    ldi     R1.w2, 0x0002
    ldi     R1.w0, 0x2020
    sbbo    R0, R1, 0, 4
    // turn on MAC unit (for multiplication)
    xor     R25, R25, R25   
    xout    0, R25, 1       
    // now fall through to abort

:CODE abort
    // clear input area in shared memory 
    xor     $x, $x, $x
    xor     $y, $y, $y
    sbco    $x, shared_ram, 0, 8
    // clear stacks
    xor	    $tos, $tos, $tos
    ldi	    $rsp, $rstackAddr
    ldi	    $psp, $stackAddr
    // clear instruction pointers
    xor     $ip, $ip, $ip
    xor     $w, $w, $w
    // signal that we have (re)started
    mov     $x, 0x01234567
    mov     $y, 0x89abcdef
    sbco    $x, shared_ram, 8, 8
    // jump to main program
    ldi	    $ip, $mainCFA 
    clr     $ip, $ip, data_address_flag
    jmp     NEXT

:CODE halt
    halt

:CODE exit                     // compiled by ; also can be used in recursion
    lbbo    $ip, $rsp, 0, 2
    add	    $rsp, $rsp, 2
;CODE

:CODE lit
    PUSH
    lbbo	$tos, $ip, 2, 4 	// move lit value to top of stack
    add	    $ip, $ip, 4		    // set instruction pointer past lit value
;CODE

:CODE dovar
    PUSH
    add	    $ip, $ip, 2
    ldi     $tos.w2, 0x0000
    lbbo	$tos.w0, $ip, 0, 2
;CODE

:CODE doconst
    PUSH
    add	    $ip, $ip, 2
    ldi     $tos.w2, 0x0000
    lbbo	$tos.w0, $ip, 0, 2
    lbbo    $tos, $tos, 0, 4
;CODE

:CODE dup
    PUSH    
;CODE

:CODE drop
    POP
;CODE

:CODE swap	
    mov     $x, $tos
    lbbo	$tos, $psp, 0, 4
    sbbo	$x, $psp, 0, 4
;CODE

:CODE over
    sbbo	$tos, $psp, 4, 4
    lbbo	$tos, $psp, 0, 4
    add	    $psp, $psp, 4
;CODE

:CODE nip
    sub	    $psp, $psp, 4
;CODE

:CODE tuck
    lbbo    $x, $psp, 0, 4
    sbbo    $tos, $psp, 0, 4
    add     $psp, $psp, 4
    sbbo    $x, $psp, 0, 4
;CODE

:CODE 2drop
    sub	    $psp, $psp, 8
    lbbo	$tos, $psp, 4, 4
;CODE

:CODE 2dup
    sbbo	$tos, $psp, 4, 4
    lbbo	$x, $psp, 0, 4
    add	    $psp, $psp, 8
    sbbo	$x, $psp, 0, 4
;CODE

:CODE rot
    sub     $x, $psp, 4
    lbbo    $z, $x, 0, 4
    lbbo    $y, $psp, 0, 4
    sbbo    $y, $x, 0, 4
    sbbo    $tos, $psp, 0, 4
    mov     $tos, $z
;CODE

:CODE -rot
    sub     $x, $psp, 4
    lbbo    $y, $x, 0, 4
    sbbo    $tos, $x, 0, 4
    lbbo    $tos, $psp, 0, 4
    sbbo    $y, $psp, 0, 4
;CODE

:CODE pick
    lsl     $tos, $tos, 2
    sub     $x, $psp, $tos
    lbbo    $tos, $x, 0, 4
;CODE

:CODE roll
    lsl     $tos, $tos, 2
    sub     $x, $psp, $tos.b0
    lbbo    $tos, $x, 0, 4
ROLLONE:
    lbbo    $y, $x, 4, 4
    sbbo    $y, $x, 0, 4
    add     $x, $x, 4
    qbgt    ROLLONE, $x, $psp
    sub     $psp, $psp, 4
;CODE

:CODE +
    lbbo	$x, $psp, 0, 4
    add	    $tos, $tos, $x
    sub	    $psp, $psp, 4
;CODE

:CODE -
    lbbo	$x, $psp, 0, 4
    sub	    $tos, $x, $tos
    sub	    $psp, $psp, 4
;CODE

:CODE @
    lbbo	$tos, $tos, 0, 4
;CODE

:CODE !
    lbbo	$x, $psp, 0, 4
    sbbo 	$x, $tos, 0, 4
    sub	    $psp, $psp, 8
    lbbo	$tos, $psp, 4, 4
;CODE 

:CODE C@
    lbbo	$tos, $tos, 0, 1
;CODE

:CODE C!
    lbbo	$x, $psp, 0, 4
    sbbo 	$x, $tos, 0, 1
    sub	    $psp, $psp, 8
    lbbo	$tos, $psp, 4, 4
;CODE

:CODE branch
    lbbo    $ip, $ip, 2, 2
    jmp     NEXT


:CODE 0branch   
    add	    $ip, $ip, 2		    // set instr ptr to next actual instruction 
    qbne	BRANCHZERO, $tos, 0
    lbbo 	$ip, $ip, 0, 2		// override instr ptr to cfa of first branch instruction
    POP
    jmp     NEXT
BRANCHZERO:
    POP
;CODE

// executeable for do
:CODE (DO)  // keep current index & limit in registers; outer ones on return stack
DOLOOP:
    sub     $rsp, $rsp, 8
    sbbo    $limit, $rsp, 4, 4
    sbbo    $index, $rsp, 0, 4
    lbbo    $limit, $psp, 0, 4
    mov     $index, $tos
    sub     $psp, $psp, 8
    lbbo    $tos, $psp, 4, 4
    ldi     $incr, 1
;CODE

// executeable for ?do
:CODE (?DO)
    add     $ip, $ip, 2
    lbbo    $x, $psp, 0, 4
    qbne    DOLOOP, $tos, $x
    sub     $psp, $psp, 8
    lbbo    $tos, $psp, 4, 4
    lbbo 	$ip, $ip, 0, 2
    jmp     NEXT

// executeable for +loop
:CODE (+LOOP)
    mov     $incr, $tos
	POP
    // fall through to (LOOP)

// executeable for loop
:CODE (LOOP)
    add     $index, $index, $incr
    add     $ip, $ip, 2
    qbge    DODONE, $limit, $index
LOOPBODY:
    lbbo 	$ip, $ip, 0, 2
    jmp     NEXT
DODONE:
    lbbo    $limit, $rsp, 4, 4
    lbbo    $index, $rsp, 0, 4
    add     $rsp, $rsp, 8
;CODE

// executeable for -loop
:CODE (-LOOP)
    mov     $incr, $tos
	POP
    sub     $index, $index, $incr
    add     $ip, $ip, 2
    qble    DODONE, $limit, $index
    jmp     LOOPBODY

// pop do loop index and limit from return stack
:CODE unloop  // would mainly be used before "exit"
    lbbo    $limit, $rsp, 4, 4
    lbbo    $index, $rsp, 0, 4
    add     $rsp, $rsp, 8
;CODE

:CODE (LEAVE)
    lbbo    $limit, $rsp, 4, 4
    lbbo    $index, $rsp, 0, 4
    add     $rsp, $rsp, 8
    add     $ip, $ip, 2
    lbbo 	$ip, $ip, 0, 2
    jmp     NEXT

:CODE i
	PUSH
    mov     $tos, $index
;CODE

:CODE j
    PUSH
    lbbo    $tos, $rsp, 0, 4
;CODE

:CODE k
    PUSH
    lbbo    $tos, $rsp, 4, 4
;CODE

:CODE and 
    lbbo	$x, $psp, 0, 4
    and	    $tos, $tos, $x
    sub 	$psp, $psp, 4
;CODE

:CODE or
    lbbo	$x, $psp, 0, 4
    or	    $tos, $tos, $x
    sub 	$psp, $psp, 4
;CODE

:CODE xor
    lbbo	$x, $psp, 0, 4
    xor	    $tos, $tos, $x
    sub 	$psp, $psp, 4
;CODE

:CODE not
    not	    $tos, $tos
;CODE

:CODE lshift
    lbbo	$x, $psp, 0, 4
    lsl	    $tos, $x, $tos
    sub 	$psp, $psp, 4
;CODE

:CODE rshift
    lbbo	$x, $psp, 0, 4
    lsr	    $tos, $x, $tos
    sub 	$psp, $psp, 4
;CODE

:CODE =
    lbbo	$x, $psp, 0, 4
    sub     $psp, $psp, 4
    qbeq    TRUE, $x, $tos

FALSE:
    xor     $tos, $tos, $tos
;CODE
         
:CODE <>
    lbbo	$x, $psp, 0, 4
    sub     $psp, $psp, 4
    qbeq    FALSE, $x, $tos
         
TRUE:
    mov     $tos, 0xffffffff
;CODE

:CODE <
    lbbo	$x, $psp, 0, 4
    sub     $psp, $psp, 4
    qblt    TRUE, $tos, $x
    jmp     FALSE

:CODE >
    lbbo	$x, $psp, 0, 4
    sub     $psp, $psp, 4
    qbgt    TRUE, $tos, $x
    jmp     FALSE

:CODE >=
    lbbo	$x, $psp, 0, 4
    sub     $psp, $psp, 4
    qbge    TRUE, $tos, $x
    jmp     FALSE

:CODE <=
    lbbo	$x, $psp, 0, 4
    sub     $psp, $psp, 4
    qble    TRUE, $tos, $x
    jmp     FALSE

:CODE r@
    PUSH
    lbbo 	$tos, $rsp, 0, 4
;CODE

:CODE >r
    sub	    $rsp, $rsp, 4
    sbbo 	$tos, $rsp, 0, 4
    POP
;CODE

:CODE r>
    PUSH
    lbbo 	$tos, $rsp, 0, 4
    add	    $rsp, $rsp, 4
;CODE

:CODE +!
    lbbo    $y, $tos, 0, 4
    lbbo    $x, $psp, 0, 4
    add     $y, $y, $x
    sbbo    $y, $tos, 0, 4
    sub     $psp, $psp, 8
    lbbo    $tos, $psp, 4, 4
;CODE
  
:CODE 1+
    add     $tos, $tos, 1
;CODE

:CODE 2+
    add     $tos, $tos, 2
;CODE

:CODE 1-
    sub     $tos, $tos, 1
;CODE

:CODE 2-
    sub     $tos, $tos, 2
;CODE

:CODE 2/
    lsr     $tos, $tos, 1
;CODE

:CODE 2*
    lsl     $tos, $tos, 1
;CODE

:CODE ?dup
    qbeq    NODUP, $tos, 0
    PUSH
NODUP:
;CODE

:CODE max
    lbbo    $x, $psp, 0, 4
    max     $tos, $tos, $x
    sub     $psp, $psp, 4
;CODE

:CODE min
    lbbo    $x, $psp, 0, 4
    min     $tos, $tos, $x
    sub     $psp, $psp, 4
;CODE

    
:CODE * 
    lbbo    R28, $psp, 0, 4
    mov     R29, $tos
    and     $tos, $tos, $tos    // NOP to allow multiply
    xin     0, R26, 8
    mov     $tos, R26           // low order 32 bits
    sbbo    R27, $psp, 0, 4     // high-order 
;CODE

// long (unsigned) division -- worst-case ~= 1 microsec
:CODE /
    lbbo    $z, $psp, 0, 4
    lmbd    $x, $tos, 1
    lmbd    $y, $z, 1
    sub     $y, $y, $x
    ldi     $x, 1
    lsl     $x, $x, $y
    lsl     $tos, $tos, $y
    xor     $y, $y, $y
ACCUM:
    qblt    SKIP, $tos, $z
    sub     $z, $z, $tos
    add     $y, $y, $x
SKIP:
    lsr     $tos, $tos, 1
    lsr     $x, $x, 1
    qbne    ACCUM, $x, 0
    mov     $tos, $y
    sub     $psp, $psp, 4
;CODE

// put current parameter stack address on stack
:CODE sp@
	PUSH
    mov     $tos, $psp
;CODE

// put current returns stack address on stack
CODE rsp@
	PUSH
    mov     $tos, $rsp
;CODE

// true and false here have same # of instructions as using constants
// but use prg mem instead of data mem
:CODE true
    PUSH
    xor     $tos, $tos, $tos
    not     $tos, $tos
;CODE

:CODE false
    PUSH
    xor     $tos, $tos, $tos
;CODE

// sleep for top-of-stack 10s-of-nanoseconds
//  resolution only 20 nanoseconds however
//  also does not account for overhead (could fix this)
:CODE sleep
    qbgt    WAKE, $tos, 2
    lsr     $tos, $tos, 1
    xor     $x, $x, $x
SLEEP:
    qbge    WAKE, $tos, $x
    add     $x, $x, 2
    and     $x, $x, $x
    jmp     SLEEP
WAKE:
    POP
;CODE

// word provided to execute primitives
: dummy
    halt     // place holder, replaced by actual address at run time
;

// execute arbitrary colon def given address on stack 
:CODE exec
    mov     $w, $tos
    // if word is primitive, must wrap it in a colon def
    qbbs    EXCOLON, $tos, data_address_flag
    ldi     $w, $dummy,
    clr     $x, $w, data_address_flag
    sbbo    $tos, $x, 0, 2
EXCOLON:
    POP
    jmp     DOCOLON


// Is a new command available?  1 = cmd, 2 = literal
:CODE ?command
    PUSH
    lbco    $tos, shared_ram, cmd_avail, 4
;CODE

:CODE @command
    PUSH
    lbco    $tos, shared_ram, cmd_value, 4
    // clear command flag
    xor     $x, $x, $x
    sbco    $x, shared_ram, cmd_avail, 4    
;CODE

// Write top of stack to shared memory
:CODE echo
    sbco    $tos, shared_ram, emit_value, 4
    // flag new value
    ldi     $x, 0x0001
    sbco    $x, shared_ram, emit_avail, 4
;CODE

// Has last emit been acknowleged?
:CODE ?read
    PUSH
    lbco    $tos, shared_ram, emit_avail, 4
    qbeq    RED, $tos, 0
    sub     $tos, $tos, 0x02
RED:
    not     $tos, $tos
;CODE


: .
    echo drop ;

// run command, if any, from main system
: oblige
    ?command ?dup if
        @command
        // if flagged as command, execute -- otherwise leave on stack
        swap 1 = if 
            exec
        then
    then ;


// *** Application code goes here ***




// loop waiting for commands to execute
: main
    begin
        oblige
    repeat
halt ;


