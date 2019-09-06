#include "common.S"

__vector_1:
__tim0_cmpa:
	; if(reading)
	sbrs gbf, RW
	rjmp cec_timer_write
		; Wrote ACK, don't need to time the high portion
		FREE CEC
		cbr gbf, ACK
		disable_timer
		DONE
	
	; assert: !ACK (write + ack handled by pcint, timer
	;  disabled in the meantime)

	cec_timer_write:

	; if(lohi == HI)
	sbrs gbf, LOHI
	rjmp cec_timer_lo
	cec_timer_hi:
		; Make sure CEC is readable
		FREE CEC

		; if(PIN(CEC)) // bus is free
		sbic PINB, CEC
		rjmp cec_bus_taken
		cec_bus_free:
			; Transition to LOW
			cbr gbf, LOHI

			; Note: In order of expected usage

			; if(state == DATA)
			cec_data_hi:
			cpi state, DATA
			brne cec_next_bit
			
			; else if(state == EOM)
			cec_eom_hi:
			cpi state, EOM
			brne cec_start_hi
				; => Await ACK (hold for 0, check for 1)
				sbr gbf, ACK
				HOLD CEC
				; write ACK is a read event, let pcint handle it
				disable_timer
				DONE

			; else if(state == START)
			cec_start_hi:
			cpi state, START
			brne cec_wait_hi
				; Start condition received => Data
				;  (Writing has no concept of addresses,
				;  just dump the contents of message)
				ldi state, DATA
				ldi it_lo, 0
				ldi nbits, 8
				rjmp cec_next_bit

			; else if(state == WAIT)
			cec_wait_hi:
			cpi state, WAIT
			brne done
				; => Attempt START condition
				ldi state, START
				HOLD CEC
				set_timeout JIFFY_START_LO
				DONE

	; else
	cec_timer_lo:
		; Transition to HIGH
		sbr gbf, LOHI
		FREE CEC

		; Sanity check
		sbis PINB, CEC
		rjmp cec_bus_taken

		cpi state, START
		brne cec_other_lo
		cec_start_lo:
			clear_timer
			set_timeout JIFFY_START_HI
			DONE

		cec_other_lo:
			; We don't actually need to know bit's value,
			;  just don't reset the timer and go until
			;  JIFFY_BIT
			set_timeout JIFFY_BIT
			DONE

cec_bus_taken:
	; CEC is INPUT and HIGH

	ldi state, WAIT
	set_timeout JIFFY_BIT*3
	DONE

cec_next_bit:
	; We'll be going low regardless
	cbr gbf, LOHI
	HOLD CEC

	; if(--nbits == 0)
	dec nbits
	brne normal_bit
	write_eom:
		ldi state, EOM

		; if(it < length)
		cp it_lo, length
		brge write_overflow
		write_continue:
			; Load the next byte while we're here
			ld data, X+
			ldi nbits, 8
			sto_1: set_timeout JIFFY_1_LO
			DONE
		
		write_overflow:
			sto_0: set_timeout JIFFY_0_LO
			DONE
	
	normal_bit:
		bst data, 7
		lsl data
		; Small 2ish opcode saving
		brts sto_1
		rjmp sto_0