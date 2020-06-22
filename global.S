#ifndef GLOBAL_S
#define GLOBAL_S

#include "config.h"

// Generic values
zero = 16 // Always kept 0
tmp = 17

// Reused in particular contexts
reg = 18
which = 18

data = 19
nbits = 20
len = 21

// Global variables
flags = 22
	// Interrupts return immediately, used to wake from sleep or
	//  detect i2c START/STOP conditions
	.equ NEST, 1
	// Whether the current CEC message is addressed to us
	.equ MINE, 2
	// CEC EOM bit
	.equ EOM, 3
	// For either i2c or CEC, whether or not the address byte has
	//  been processed yet.
	// Note: Might be mutually exclusive with EOM
	.equ WHO, 4
	// Whether or not the buffer contains data from CEC
	.equ DIRTY, 5

cec_addr = 23
length = 24

stack_unwind = 25

// RAM allocation
i2c_reg = RAMSTART
buffer = i2c_reg + 1

.altmacro

.macro await_low pin
	await_low_loop\@:
		sbic PINB, \pin
			rjmp await_low_loop\@
.endm
.macro await_high pin
	await_high_loop\@:
		sbis PINB, \pin
			rjmp await_high_loop\@
.endm

.macro io_cpi io, i
	in tmp, \io
	cpi tmp, \i
.endm

.macro set_Y y
	ldi YH, hi8(\y)
	ldi YL, lo8(\y)
.endm
.macro set_Z z
	ldi ZH, hi8(\z)
	ldi ZL, lo8(\z)
.endm

.macro set_flag flag
	sbr flags, 1<<\flag
.endm
.macro clear_flag flag
	cbr flags, 1<<\flag
.endm

.macro HOLD pin
	// Output
	sbi DDRB, \pin
.endm
.macro FREE pin
	// Input
	cbi DDRB, \pin
.endm

.macro outi io, i
	// if \i is 0, we could use zero, but macros apparently can't
	//  recognize that.
	ldi tmp, \i
	out \io, tmp
	
	/*
	.print "\i"
	.if \i
		ldi tmp, \i
		out \io, tmp
	.else
		out \io, zero
	.endif
	*/
.endm

.macro dec_loop it, lbl
	dec \it
	brne \lbl
.endm

.macro BEEP
	HOLD CEC
	FREE CEC
.endm

#define LOW 0
#define CHANGE 1
#define FALL 2
#define RISE 3
//*

.macro dump_bit value, bit
	sbrs \value, \bit
		FREE CEC
	sbrc \value, \bit
		HOLD CEC
.endm

.macro dump_byte value
	BEEP
	BEEP
	
	dump_bit \value, 7
	dump_bit \value, 6
	dump_bit \value, 5
	dump_bit \value, 4
	dump_bit \value, 3
	dump_bit \value, 2
	dump_bit \value, 1
	dump_bit \value, 0
	
	BEEP
	BEEP
.endm

.macro case reg, value, lbl
	cpi \reg, \value
	breq \lbl
.endm

.macro enable_int0
	sbi EIMSK, 0
.endm
.macro disable_int0
	cbi EIMSK, 0
.endm
.macro set_int0_mode im
	outi EICRA, \im
.endm

.macro enable_pcint0
	// Write 1 to flag register to clear any pending interrupts
	sbi PCIFR, 0
	sbi PCICR, 0
.endm
.macro disable_pcint0
	cbi PCICR, 0
.endm

.macro enable_tim0_compa
	in tmp, TIMSK0
	sbr tmp, 1<<OCIE0A
	out TIMSK0, tmp
.endm
.macro disable_tim0_compa
	in tmp, TIMSK0
	cbr tmp, 1<<OCIE0A
	out TIMSK0, tmp
.endm

.macro enable_tim0_compb
	in tmp, TIMSK0
	sbr tmp, 1<<OCIE0B
	out TIMSK0, tmp
.endm
.macro disable_tim0_compb
	in tmp, TIMSK0
	cbr tmp, 1<<OCIE0B
	out TIMSK0, tmp
.endm

.macro set_timeout_a ticks
	outi OCR0AH, hi8(\ticks)
	outi OCR0AL, lo8(\ticks)
.endm

.macro set_timeout_b ticks
	outi OCR0BH, hi8(\ticks)
	outi OCR0BL, lo8(\ticks)
.endm

.macro restart_timer
	out TCNT0H, zero
	out TCNT0L, zero
.endm

.macro if_set flag, lbl
	sbrc flags, \flag
		rjmp \lbl
.endm

.macro if_clear flag, lbl
	sbrs flags, \flag
		rjmp \lbl
.endm

//*/

#define enable_cec enable_int0
#define disable_cec disable_int0

#define enable_i2c enable_pcint0
#define disable_i2c disable_pcint0

#endif
