#include "global.h"

.equ __tmp_reg__, 16

.org 0x0000
.section .vectors
__vectors:
	rjmp main // __vector_0 RESET
	reti //rjmp __vector_1 // INT0
	// Only fire PCINT0 if SCL is high (START/STOP)
	sbis PINB, SCL // __vector_2 PCINT0
		reti // __vector_3 TIM0_CAPT (unused)
	rjmp __vector_2 // __vector_4 TIM0_OVF (unused)
	
	// Compb just returns (used for timeout)
	ret // __vector_5 TIM0_COMPA
	// If compa triggers, a CEC event took too long - unwind stack and
	//  return to main
	ldi __tmp_reg__, STACK_UNWIND // __vector_6 TIM0_COMPB
	out SPL, __tmp_reg__ // __vector_7 ANA_COMP (unused)
	ret // __vector_8 WDT (unused)
	// __vector_9 VLM
	// __vector_10 ADC

.section .text
