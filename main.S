#include "config.h"

#include "global.S"
#include "head.S"
#include "cec.S"
#include "i2c.S"

main:
	// Disable unused modules
	sbi ACSR, ACD // Analog Comparator Disable
	outi PRR, 0b10
	sbi DIDR0, RESET // Digital Input Disable
	
	// Allow buses to float high in input mode
	outi PUEB, 0b0111 // Pull-Up Enable
	
	// Pull line low when in output mode
	//PORTB = 0
	
	// Sleep enable = 1
	// Sleep mode = 0 = idle
	outi SMCR, 1

	// Default to all input ("free")
	//DDRB = 0
	
	ldi zero, 0
	ldi stack_unwind, RAMEND - 2
	
	// Initialize program state
	
	ldi length, 0
	ldi cec_addr, CEC_DEFAULT
	
	// Set up interrupts
	
	// External interrupt (INT0)
	
	set_int0_mode FALL
	// Disabled so we can use CEC for debugging
	//enable_int0
	
	// Enable timer
	outi TCCR0B, 1
	
	// Pin change interrupt (PCINT0)
	sbi PCMSK, SDA
	enable_pcint0
	
	// Clock prescaling factor 1 (8 MHz)
	outi CCP, 0xD8 // Config Change Protection
	out CLKPSR, zero // 8 MHz
	
	main_loop:
		sei
		sleep
		rjmp main_loop