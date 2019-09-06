#include "common.S"

.org 0x0000
__vectors:
	rjmp main
	rjmp __vector_1 ; INT
	rjmp __vector_2 ; PCINT
	reti
	reti
	rjmp __vector_5 ; Timer

#include "cec-timer.S"
#include "pcint.S"
#include "scl-int0.S"

.global main
main:
	;; Setup all the registers

	; TCCR0B = 0b101
	ldi tmp, 0b101
	out TCCR0B, tmp ; Internal clock / 1024

	; TIMSK0 = 0b000

	; EIMSK = 1
	sbi EIMSK, 0 ; Enable SCL as external interrupt

	; EICRA = 0b01
	sbi EICRA, 0 ; Logical change generates INT0

	; DDRB = 0b0000

	; PCMSK = 0b0011
	ldi tmp, 0b0011
	out PCMSK, tmp ; Set SDA and CEC to use pin change
	sbi PCICR, 0 ; Enable pin change interrupt
	
	; PUEB = 0b1111;
	ldi tmp, 0b1111 ; Set all pins to pull-up
	out PUEB, tmp

	; DIDR0 = 0b1000
	sbi DIDR0, 3 ; Disable pin 3 (unused)
	
	; PRR =  0b10
	;sbi PRR, 1 ; Disable ADC module
	
	; SMCR = 0b1001
	ldi tmp, 0b1001
	out SMCR, tmp

	;; Set up the program state

	ldi state, IDLE

	sbic PINB, SDA
		sbr gbf, OLD_SDA
	
	sbic PINB, CEC
		sbr gbf, OLD_CEC

	ldi cmd, state ; state = IDLE = 0
	ldi length, 0
	ldi nbits, 0
	ldi cec_addr, 0x15

	; Note: don't need to initialize X until cmd is non-zero

	sei ; Enable all interrupts

	do_sleep:
		sleep
		rjmp do_sleep
