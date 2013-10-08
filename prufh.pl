#!/usr/bin/perl
##########################################################################
#                                                                        #
#    prufh.pl                                                            #
#                                                                        #
# Copyright 2013 John C Silvia                                           #
#                                                                        #
# This file is part of prufh.                                            #
#                                                                        #
#    prufh is free software: you can redistribute it and/or modify       #
#    it under the terms of the GNU General Public License as published by#
#    the Free Software Foundation, either version 3 of the License, or   #
#    (at your option) any later version.                                 #
#                                                                        #
#    prufh is distributed in the hope that it will be useful,            #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of      #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the       #
#    GNU General Public License for more details.                        #
#                                                                        #
#    You should have received a copy of the GNU General Public License   #
#    along with prufh.  If not, see <http://www.gnu.org/licenses/>.      #
#                                                                        #
#                                                                        #
##########################################################################
use strict;
use Getopt::Std;
use FileHandle;

# Register definitions
our $tos = 'R4';
our $w = 'R5';
our $x = 'R6';
our $y = 'R7';
our $z = 'R8';
our $psp = 'R10';
our $rsp = 'R12';
our $ip = 'R14';

our $limit = 'R16';
our $incr  = 'R17';
our $index = 'R18';

my $next = '0x0001';            # location of next 

our $primend = "jmp $next";    # def of ; for primitive

# read entire file into array (impossible for it to be too big)
my @lines;

my %words = ();         # hash of names -> addresses

my $address = 0;        # current program address
my $here = 0x8000;      # current data address (with high-bit flag set)

my $linenum = 0;        # source code line number

my $curname;            # name of current word
my $assembling = -1;    # assembler mode? (start in assembler for "next")
my $compiling = 0;      # compiling colon defs?

my $variable = 0;       # flag that a variable is being created
my $constant = 0;       # flag that a constant is being created
my $value = 0;          # value of current constant

my @dictionary;         # sequential array of word addresses (forth program)
my @loop;               # fifo stack for resolving loop addresses

my $bflag = '0x&&&&';   # temporary place holder for "begin" loop addresses
my $dflag = '0x!!!!';   # temporary place holder for "do loop" addresses
my $iflag = '0x????';   # temporary place holder for "if else then" addresses

my %vars = ();          # hash of variable and constant names -> addresses

my $naming = 0;         # flag that a name is expected
my $macrodef = 0;       # flag that we are in an assembly macro definition



our $opt_f = "prufh.4th";  # default program name

my $assembler = "";

getopts("ha:f:");

my $file = $opt_f;
my $assembler = our $opt_a;

if (our $opt_h)
{
    print "Usage: prufh.pl [-a ASSEMBLER] [-f SOURCE]\n\n";
    print "-f <file>        process file <file>\n";
    print "-a <assembler>   automatically run assembler at <file>\n\n";
    print " Example:  ./prufh.pl -a \"../utils/pasm -V2\" -f myprufh.4th\n\n";
    exit;
}

# derive file names
my $debug = $file =~ s/\.4th/.dbg/r;
my $datafile = $file =~ s/\.4th/.dat/r;
my $prgfile = $file =~ s/\.4th/.prg/r;
my $deffile = $file =~ s/\.4th/.defs/r;


# set up array of file handles
my @files;      

open(TXT, "> $debug") or die "Can not open debug text file.\n";

push (@files, openInput($file));

while(scalar @files) {
    compile();
}


close(TXT);

# save data memory image to file
open(DATAM, "> $datafile") or die "Can not open data memory file.\n";
    foreach(@dictionary) {
#        print DATAM "$_  ";
        /^0x/ and do {print DATAM "$_\n"; next;};
        printf(DATAM "%#0.4x\n", $_);
    }
close(DATAM);

$here -= 0x8000;  # strip high bit to get actual address in data memory


# Report memory usage
print "here = $here\n";
my $dsize = @dictionary * 2;
print "dictionary size = $dsize\n";
print "program lines = $address\n";
$address *= 4;
print "program memory used = $address\n";


$here += 16;      # provide buffer space between end of dict and start of stack
$here = sprintf "%#0.4x", $here;  # change here to hex string

# get address of main program
my $main = sprintf "%#0.4x", $words{'main'};


# Reprocess debug file to produce input for assembler
open(PRGM, "> $prgfile") or die "Can not open program memory file.\n";
open(TXT, "< $debug") or die "Can not reopen debug text file.\n";
while(<TXT>) {
    # skip empty lines and data memory entries
    /^\s*\d*\s+\S*\s*$/ and next;
    /^f/ and next;

    # skip high-level forth definitions
    /^\s*\d*\s+\S*\s*>/ and next;


    # set entry point for forth program
    s/\$mainCFA/$main/;
    # set location of stack
    s/\$stackAddr/$here/;
    # set location of return stack
    s/\$rstackAddr/0x1ff0/;

    # write assembler input skipping comments
    /^\s*\d*\s*\S*\s*(.+)/ and do { print PRGM "$1\n" unless $1 =~ /^\/\// };
}
close(TXT);
close(PRGM);


# Save table of word addresses
open(TXT, "> $deffile") or die "Can not open words text file.\n";
    my $sz = scalar keys %words;
    print TXT "$sz\n\n";
    foreach my $key (sort(keys %words)) {
           printf(TXT "%-12s    %#0.4x\n", $key, $words{$key});
    }
    print TXT "\n\n";
    foreach my $key (sort byAddr(keys %words)) {
           printf(TXT "%#0.4x    %s\n", $words{$key}, $key);
    }
close(TXT);


# Optionally run assembler if location has been provided
if($assembler) {
    exec "$assembler -b $prgfile\n" or 
    print "\nError! $assembler not found\n\n";
}


exit;

# Add literal to dictionary
sub dolit {
    my ($num) = @_;

    push(@dictionary, $words{'lit'});
    $here += 2;

    donum($num, 'literal', 'lit');
}

# Write number to dictionary
sub donum {
    my ($num, $type, $name) = @_;
    my ($numL, $numH);

    # convert decimal, binary, octal, and hex formats
    $num = oct($num) if $num =~ /^0/;

    # split value into 2 16-bit hex numbers
    $num = sprintf("%0.8x", $num);

    $num =~ /(....)(....)/;
    $numL = "0x$2";
    $numH = "0x$1";

    printf(TXT "\n%0.4u    %#0.4x    > $type $numH $numL", 
           $linenum, $words{$name});

    # add to dictionary as little-endian
    push(@dictionary, $numL);
    push(@dictionary, $numH);
    $here += 4;
}


# resolve possible forward references used to exit do loops early
sub fwdref {
    my ($addr, $do, $marker) = @_;
    my $start = 0;

    my $do = hex($do);

    # find begining index of do loop
    #  -2 to cover address field of loop beginning
    # divide by two because every dict entry is 2 bytes
    if($do > 0) {
        $start = ($do - 2) / 2; 
    }
    for my $i ($start .. $#dictionary) {
        $dictionary[$i] = strip($addr) if ($dictionary[$i] eq $marker);
    }
}

# Clear high-bit flag from data addresses and return as string
sub strip {
    my ($addr) = @_;

    $addr -= 0x8000 if $addr >= 0x8000;

    return sprintf("%#0.4x", $addr);
}

# Used to sort dictionary by address value
sub byAddr {
   $words{$a} <=> $words{$b};
}


# return handle for input file
sub openInput {
    my ($filename) = @_;
    my $fh = new FileHandle;

    $fh->open("< $filename") or die "Can not open input file, $file.\n";
    return $fh;
}


# Parse soruce file 
# builds forth dictionary and preprocesses assembly code
sub compile {
    my $fh = $files[-1];

    while(<$fh>) {
        $linenum++;         # keep track of input lines for debugging
        my $bump = 0;       # flag assembly instruction found, will increase address
        my $pseudo = 0;     # number of additional lines added by assembly pseudo op
        my $fstart = $here;
        printf TXT '%0.4u    %#0.4x    ', $linenum, $address;

        # include new source file
        /^#include\s+(.*)\s*$/ and do {push(@files, openInput($1)); 
                            $fh = $files[-1]; next;};
        
        # ignore comments, blank lines, and assembler directives
        /^\s*$/ and do {print TXT "\n"; next;};
        /^\s*\/\// and do {print TXT "$_"; next;};
        /^\s*\.macro\s/ and do {$macrodef = -1; print TXT "$_"; next;};
        /^\s*#\S+/ and do {print TXT $_; next;};
        /^\s*\.(?!endm)\S+/ and do {print TXT $_; next;};

        # parse each line
        my @line = split();
        foreach (@line) {
            # record name, location of new definition
            if($naming) {
                $naming = 0;
                $curname = $_;
                if ($assembling) {
                    # def resides in program memory
                    $words{$curname} = $address ;
                    print TXT "// : $curname";
                } else {
                    # def resides in data memory
                    $words{$curname} = $here;
                    print TXT "> : $curname";
                }
                next;
            }
            /^\/\// and last;  # skip comment lines

            # compile start of new code definition
            /^:CODE$/ and do {$naming = -1; $assembling = -1; next;};

            if($assembling) {
                # handle end of code definition by jumping to next
                /^;CODE$/ and do {print TXT $primend; $assembling = 0; 
                                    $bump = -1; next;};

                # pass assembler label on to output unchanged
                /^.+:$/ and do { print TXT "$_ "; next;};

                # macros for pushing and popping parameter stack
                /^PUSH$/ and do { print TXT "add $psp, $psp, 4\n";
                            printf TXT "%0.4u    %#0.4x    sbbo $tos, $psp, 0, 4",
                            $linenum, $address + 1;
                            $address += 2; next;};
                /^POP$/ and do { print TXT "lbbo $tos, $psp, 0, 4\n";
                            printf TXT "%0.4u    %#0.4x    sub $psp, $psp, 4", 
                            $linenum, $address + 1;
                            $address += 2; next;};

                # adjust address for mov pseudo op
                /^mov$/ and do { 
                            # if the source op is numeric, may require 2 ops
                            if($line[2] =~ /^[\d|#]/ ) {
                                my $src = join(' ', @line[2..$#line]);
                                $src =~ s/#//;
                                $src = eval $src;
                                $pseudo++ if $src >= 0x00010000;
                            }
                            print TXT "$_ "; next;};


                # substitute register values
                s/^\$tos(\.\S+$|,$|$)/$tos$1/;
                s/^\$ip(\.\S+$|,$|$)/$ip$1/;
                s/^\$psp(\.\S+$|,$|$)/$psp$1/;
                s/^\$rsp(\.\S+$|,$|$)/$rsp$1/;
                s/^\$w(\.\S+$|,$|$)/$w$1/;
                s/^\$x(\.\S+$|,$|$)/$x$1/;
                s/^\$y(\.\S+$|,$|$)/$y$1/;
                s/^\$z(\.\S+$|,$|$)/$z$1/;
                s/^\$limit(\.\S+$|,$|$)/$limit$1/;
                s/^\$index(\.\S+$|,$|$)/$index$1/;
                s/^\$incr(\.\S+$|,$|$)/$incr$1/;

                # don't add macros to dictionary
                if($macrodef) {
                    /^\s*\.endm/ and $macrodef = 0;
                    print TXT "$_ "; 
                    next;
                }

                # substitute address of special word used by "exec"
                s/^\$dummy(\.\S+$|,$|$)/$words{'dummy'}$1/;

                print TXT "$_ ";
                $bump = -1;           # flag that instruction is using memory
            } elsif ($compiling) {
                # end of definition
                /^;\s*$/ and do { $_ = 'exit'; $compiling = 0;}; 

                # handle literal values in definitions
                /^0x[0123456789abcdefABCDEF]+$/ and do { dolit($_); next;};
                /^0b[01]+$/ and do { dolit($_); next;};
                /^\d+$/ and do { dolit($_); next;};

                # compile branching words
                /^begin$/ and do { push(@loop, strip($here)); 
                                print TXT "// BEGIN";next;};  
                /^until$/ and do { push(@dictionary, $words{'0branch'});
                                push(@dictionary, pop(@loop)); $here += 4; 
                                print TXT "// UNTIL"; next;};
                /^repeat$/ and do { push(@dictionary, $words{'branch'}); 
                                $fstart = pop(@loop); 
                                push(@dictionary, $fstart);
                                $here += 4; 
                                fwdref($here, $fstart, $bflag); 
                                print TXT "// REPEAT"; next;};
                /^while$/ and do { push(@dictionary, $words{'0branch'}); 
                                push(@dictionary, $bflag ); $here += 4; 
                                print TXT "// WHILE"; next;};

                /^do$/ and do { push(@dictionary, $words{'(DO)'}); 
                                $here += 2; 
                                push(@loop, strip($here)); 
                                print TXT "\t// DO"; next;};
                /^\?do$/ and do { push(@dictionary, $words{'(?DO)'}); 
                                push(@dictionary, $dflag ); 
                                $here += 4; 
                                push(@loop, strip($here)); 
                                print TXT "\t// ?DO"; next;};
                /^leave$/ and do { push(@dictionary, $words{'(LEAVE)'});
                                push(@dictionary, $dflag ); 
                                $here += 4;
                                print TXT "\t// LEAVE"; next;};
                /^loop$/ and do { push(@dictionary, $words{'(LOOP)'});
                                $fstart = pop(@loop); 
                                push(@dictionary, $fstart); 
                                $here += 4; 
                                fwdref($here, $fstart, $dflag); 
                                print TXT "\t// LOOP"; next;};
                /^\+loop$/ and do { push(@dictionary, $words{'(+LOOP)'}); 
                                $fstart = pop(@loop); 
                                push(@dictionary, $fstart); 
                                $here += 4; 
                                fwdref($here, $fstart, $dflag); 
                                print TXT "\t// +LOOP"; next;};
                /^\-loop$/ and do { push(@dictionary, $words{'(-LOOP)'}); 
                                $fstart = pop(@loop); 
                                push(@dictionary, $fstart); 
                                $here += 4; 
                                fwdref($here, $fstart, $dflag); 
                                print TXT "\t// -LOOP"; next;};

                /^if$/ and do { push(@dictionary, $words{'0branch'}); 
                                push(@dictionary, $iflag); 
                                push(@loop, strip($here));
                                $here += 4; 
                                print TXT "\t// IF"; next;};
                /^else$/ and do { $here += 4; fwdref($here, pop(@loop), $iflag);
                                push(@dictionary, $words{'branch'}); 
                                push(@dictionary, $iflag); 
                                push(@loop, strip($here));
                                print TXT "\t// ELSE"; next;};
                /^then$/ and do { fwdref($here, pop(@loop), $iflag); 
                                print TXT "\t// THEN"; next;};

                # compile word addresses into dictionary
                exists $words{$_} or die "Undefined word, \"$_\", in line #$linenum\n";
                push(@dictionary, $words{$_});
                printf( TXT "\n%0.4u    %#0.4x    > $_", $linenum, $words{$_});
                $here += 2;
                if(exists $vars{$_}) {
                    push(@dictionary, $vars{$_});
                    $here += 2;
                }
            } else {  # not inside colon def or code def

                # forth variable name
                if($variable) {
                    $variable = 0;
                    $words{$_} = $words{'dovar'};
                    $vars{$_} = strip($here);
                    donum(0, 'variable', 'dovar');
                    next;
                }
                # forth constant name
                if($constant) {         
                    $constant = 0;
                    $words{$_} = $words{'doconst'};
                    $vars{$_} = strip($here);
                    donum($value, 'constant', 'doconst');
                    next;
                }

                # start of colon definition
                /^:\s*$/ and do {$naming = -1; $compiling = -1; next;};

                # save numeric values for subsequent constant
                /^\d+$/ and do { $value = $_; next;};       
                 /^0x[0123456789abcdefABCDEF]+$/ and do { $value = $_; next;};
                /^0b[01]+$/ and do { $value = $_; next;};

                # prepare to handle variable or constant name
                /^variable$/ and do {$variable = -1; next;};
                /^constant$/ and do {$constant = -1; next;};
            }
        }
        $address++ if $bump;
        $address += $pseudo;
        print TXT "\n";
        $bump = 0;
        $pseudo = 0;
    }
    $fh = pop(@files);
    $fh->close;
}


