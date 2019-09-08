#include "common.S"

/**
 * The PCINT0 is used for CEC read events and the i2c
 *  START/STOP conditions, which occur when SDA changes
 *  while SCL is high.
**/

__vector_2:
__pcint0:
	; We don't need to check for SDA/CEC change unless
	;  we're reading, write+ACK or read+!ACK
	mov tmp, gbf
	lsr tmp
	eor tmp, gbf
	sbis tmp, RW ; skip if RW^ACK
	rjmp done ; Must be writing to the bus, exit

	; Set up for determining rising/falling edge
	in tmp, PINB
	eor tmp, gbf

	; If we're in idle, listen to either bus
	ldi state, IDLE
	brne check_bus
	sbrs tmp, CEC
	rjmp check_sda
	rjmp check_cec

	; ...otherwise, only need to pay attention to the bus we're on
	check_bus:
	sbrc gbf, I2CEC
	rjmp check_sda

	check_cec:
		; Early exit if it wasn't a change on CEC
		sbrs tmp, CEC
		rjmp done
		
		; Toggle the bit (no eori?)
		ldi tmp, 1<<OLD_CEC
		eor gbf, tmp
		
		; if(PIN(CEC))
		sbis PINB, CEC
		rjmp cec_falling
		cec_rising:
			in tmp, COUNTER

			; if(COUNTER >= START_LO - E)
			cpi tmp, JIFFY_START_LO - JIFFY_E
			brlt cec_check_0
			cec_start:
				; START
				cbr gbf, I2CEC
				ldi state, WHO
				ldi nbits, 9 ; 8 + EOM
				DONE
			
			; else if(COUNTER >= ZERO_LO - E)
			cec_check_0:
			cpi tmp, JIFFY_0_LO - JIFFY_E
			brlt cec_check_1
				clt ; T = 0
				rjmp cec_bit
			
			; else if(COUNTER >= ONE_LO - E)
			cec_check_1:
			cpi tmp, JIFFY_1_LO - JIFFY_E
			brlt done ; else return
				set ; T = 1
				; implicit rjmp cec_bit
			
			cec_bit:

			; if(--nbits != 0)
			dec nbits
			breq cec_process_data
			cec_still_reading:
				lsl data ; data <<= 1
				bld data, 1 ; data |= T
				DONE

			; else
			cec_process_data:
				; if(state == WHO)
				cpi state, WHO
				brne cec_proc_data
				cec_proc_who:
					; Indicates a POLL message
					; if(high(data) == low(data))
					mov tmp, data
					swap tmp
					cp tmp, data
					brne cec_notpoll
					cec_ispoll:
						; if((data&0x0f) == cec_addr)
						andi data, 0x0f
						cp data, cec_addr
						brne cec_notme
						cec_me:
							; We own this address, ACK
							sbr gbf, ACK
							DONE
						
						; else
						cec_notme:
							; We only need to record the address now, no
							;  need to wait for the ACK because a NAK
							;  implies the inciting device took the address
							ldi state, IDLE

							;;; {build bit}
							ldi tmp, 1
							bst data, 3 ; T = data&0b1000
							cbr data, 3
							; Jump immediately to the condition, use
							;  the Z flag from cbr
							rjmp build_taken_bit_cond
							; AVR doesn't have a variable lsl instruction
							build_taken_bit:
								lsl tmp ; tmp <<= 1
								dec data ; while(--data)
								build_taken_bit_cond:
								brne build_taken_bit
							;;; {/build bit}

							brts cec_who_hi
							cec_who_lo:
								or taken_lo, tmp
								DONE
							cec_who_hi:
								or taken_hi, tmp
								DONE
					; else
					cec_notpoll:
						; Technically need to read the EOM first
						ldi state, EOM
						ldi it_lo, 0
						ldi length, 0
						DONE
				
				; else if(state == EOM)
				cec_proc_eom:
				cpi state, EOM
				brne cec_proc_data
					brtc cec_eom_cont
					cec_eom_done:
						ldi state, IDLE
						DONE
					cec_eom_cont:
						ldi state, DATA
						DONE

				; else
				cec_proc_data:
					st it+, data
					inc length

					; if(it_lo >= 16)
					cpi length, 16
					brlt done
						; Ignore whatever else is sent
						ldi state, IDLE
						DONE

		; else
		cec_falling:
			; if(reading && gbf.ACK)
			sbrc gbf, RW
			sbrs gbf, ACK ; RW=1
			rjmp done
				; Master requires ACK, send logical 1
				HOLD CEC
				
				clear_timer
				set_timeout JIFFY_1_LO
				enable_timer
				DONE

	check_sda:
		; Early exit if it wasn't a change on SDA
		sbrs tmp, SDA
		rjmp done

		; Toggle the bit (no eori?)
		ldi tmp, 1<<OLD_SDA
		eor gbf, tmp

		; Check for START/STOP condition, which can only
		;  happen if SDA changes while SCL is high
		; if(PIN(SCL))
		sbis PINB, SCL
		rjmp done
			; if(PIN(SDA))
			sbis PINB, SDA
			rjmp sda_falling
			sda_rising:
				; STOP
				ldi state, IDLE
				DONE

			sda_falling:
				; START
				sbr gbf, I2CEC
				ldi nbits, 8
				ldi it_lo, 0
				ldi length, 0
				ldi state, WHO
				DONE