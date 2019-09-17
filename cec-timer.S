#include "common.S"

/**
 * The TIM0_CMPA interrupt is only used when writing to
 *  the CEC bus, including an ACK during reading.
**/

__vector_1:
__tim0_cmpa:
	; if(reading)
	if_unset RW, cec_timer_write
		; Wrote ACK, don't need to time the high portion
		FREE CEC
		clear_flag ACK
		disable_timer
		DONE
	
	; assert: !ACK (write + ack handled by pcint, timer
	;  disabled in the meantime)

	cec_timer_write:

	; if(HILO == HI)
	if_unset HILO, cec_timer_lo
	cec_timer_hi:
		FREE CEC
		if_low CEC, cec_bus_taken
		cec_bus_free:
			; Transition to LOW
			clear_flag HILO
			HOLD CEC

			; switch(state)
			if_state DATA, done
			if_state EOM, cec_eom_hi
			if_state START, cec_start_hi
			if_state WAIT, cec_wait_hi
			DONE
			
			cec_eom_hi:
				ldi state, DATA
				set_flag ACK
				mov tmp, length
				addi tmp, message
				cp it_lo, tmp
				brlt bit_0
				rjmp bit_1

				; => Await ACK (hold for 0, check for 1)
				set_flag ACK
				; write ACK is a read event, let pcint handle it
				disable_timer
				DONE

			cec_start_hi:
				; Start condition received => Data
				;  (Writing has no concept of addresses,
				;  just dump the contents of message)
				ldi state, DATA
				ldi it_lo, 0
				; Skip bounds checks and load the "next" byte
				rjmp cec_next_bit

			cec_wait_hi:
				; => Attempt START condition
				ldi state, START
				set_timeout JIFFY_START_LO
				DONE

	; else
	cec_timer_lo:
		; Transition to HIGH
		set_flag HILO
		FREE CEC

		; Sanity check
		if_low CEC, cec_bus_taken

		if_state START, cec_start_lo
		cec_other_lo:
			; We don't actually need to know bit's value,
			;  just don't reset the timer and go until
			;  JIFFY_BIT
			set_timeout JIFFY_BIT
			DONE
			
		cec_start_lo:
			set_timeout JIFFY_START
			DONE

cec_bus_taken:
	; CEC is INPUT and LOW

	ldi state, WAIT
	set_timeout JIFFY_BIT*3
	DONE

cec_next_bit:
	; assert: HILO=0, HOLD CEC

	rcall get_next_bit
	brne normal_bit
	brge cec_overflow

	write_eom:
		ldi state, EOM

	normal_bit:
	brts bit_1
	bit_0:
		set_timeout JIFFY_0_LO
		DONE
	
	bit_1:
		set_timeout JIFFY_1_LO
		DONE
	
	cec_overflow:
		rjmp ignore_rest