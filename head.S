#include "config.h"
#include "global.S"

.org 0x0000
.section .vectors
__vectors:
	rjmp main // __vector_0 RESET
	rjmp __vector_1 // INT0
	// Only fire PCINT0 if SCL is high (START/STOP)
	sbis PINB, SCL // __vector_2 PCINT0
		reti // __vector_3 TIM0_CAPT
	rjmp __vector_2 // __vector_4 TIM0_OVF
	
	// If compa triggers, a CEC event took too long - unwind stack and
	//  return to main
	out SPL, stack_unwind // __vector_5 TIM0_COMPA
	// Compb just returns
	ret // __vector_6 TIM0_COMPB
	// __vector_7 ANA_COMP
	// __vector_8 WDT
	// __vector_9 VLM
	// __vector_10 ADC

.section .text
