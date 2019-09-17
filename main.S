#include "common.S"

.org 0x0000
__vectors:
	rjmp main ; RESET
	rjmp __vector_1 ; INT
	rjmp __vector_2 ; PCINT
	reti ; Timer input capture
	rjmp __vector_4 ; Timer overflow
	rjmp __vector_5 ; Timer

; Sanity check, return to a known state if the timer overflows
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
	;; Setup all the registers

	; TCCR0B = 0b101
	ldi tmp, 0b101
	out TCCR0B, tmp ; Internal clock / 1024

	; Enable timer overflow interrupt
	sbi TIMSK0, 0

	; SCL generates INT0
	sbi EIMSK, 0

	; INT0 from logical change
	sbi EICRA, 0

	; PCMSK = 0b0011
	ldi tmp, 0b0011
	out PCMSK, tmp ; Set SDA and CEC to use pin change
	sbi PCICR, 0 ; Enable pin change interrupt
	
	; PUEB = 0b1111;
	ldi tmp, 0b1111 ; Set all pins to pull-up
	out PUEB, tmp

#ifndef DIRTY_PIN
	sbi DIDR0, 3 ; Disable pin 3 (unused)
#else
	sbi DDRB0, DIRTY_PIN ; Set dirty pin to output
#endif

	; PRR =  0b10
	;sbi PRR, 1 ; Disable ADC module
	
	; Sleep mode = standby + sleep-enable
	ldi tmp, 0b1001
	out SMCR, tmp

	;; Set up the program state

	ldi state, IDLE

	sbic PINB, SDA
		sbr gbf, OLD_SDA
	
	sbic PINB, CEC
		sbr gbf, OLD_CEC

	ldi cmd, 0
	ldi length, 0
	ldi nbits, 0
	ldi cec_addr, CEC_ADDR_DEFAULT

	; Note: don't need to initialize X until cmd is non-zero

	sei ; Enable all interrupts

	do_sleep:
		sleep
		rjmp do_sleep
