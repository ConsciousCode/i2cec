#include "common.S"

.org 0x0000
__vectors:
	rjmp main // RESET
	rjmp __vector_1 // INT
	rjmp __vector_2 // PCINT
	reti // Timer input capture
	rjmp __vector_4 // Timer overflow
	rjmp __vector_5 // Timer

// Sanity check, return to a known state if the timer overflows
__vector_4:
timer_overflow:
	disable_timer
	ldi state, IDLE
	DONE

#include "cec-timer.S"
#include "pcint.S"
#include "funcs.S"
#include "scl-int0.S"

.global main
main:
	/// Setup all the I/O registers

	ldi tmp, 0b101
	out TCCR0B, tmp // Internal clock / 1024

	// Enable timer overflow interrupt
	// TIMSK0 = 0x2b which is outside sbi's range of 0-0x1f
	ldi tmp, 1
	out TIMSK0, tmp

	// SCL generates INT0
	sbi EIMSK, 0

	// INT0 from logical change
	sbi EICRA, 0

	ldi tmp, 0b0011
	out PCMSK, tmp // Set SDA and CEC to use pin change
	sbi PCICR, 0 // Enable pin change interrupt
	
	ldi tmp, 0b1111 // Set all pins to pull-up
	out PUEB, tmp

#ifndef DIRTY_PIN
	sbi DIDR0, 3 // Disable pin 3 (unused)
#else
	sbi DDRB0, DIRTY_PIN // Set dirty pin to output
#endif

	// PRR =  0b10
	//sbi PRR, 1 // Disable ADC module
	
	// Sleep mode = standby + sleep-enable
	ldi tmp, 0b1001
	out SMCR, tmp

	/// Set up the program state

	// Assert: CEC, SDA, SCL are all input

	clr gbf

	// set old_{cec, sda} to current values
	in tmp, PINB
	andi tmp, (1<<CEC)|(1<<SDA)
	eor gbf, tmp

	clr state // state = IDLE
	//> data is a buffer so don't bother clearing
	clr nbits
	//> tmp is set for every use so don't bother clearing
	clr length
	ldi cec_addr, CEC_ADDR_DEFAULT
	clr cmd

	// Clear the memory registers
	clr it_lo
	clr it_hi
	clr taken_lo
	clr taken_hi
	clr Z_lo
	clr Z_hi

	sei // Enable all interrupts

	// All processing is done in interrupts
	do_sleep:
		sleep
		rjmp do_sleep
