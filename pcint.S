#include "common.S"

; SDA or CEC change
__vector_2:
__pcint0:
	in tmp, PINB
	; NOTE: Make sure gbf stores old_* in the same bit
	;  location as CEC/SDA
	eor tmp, gbf
	sbrc tmp, CEC
	rjmp sda_change
	cec_change:
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
				ldi state, WHO
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
			
			cec_bit:

			; if(state == POLL)
			cpi state, POLL
			brne cec_notpolling
			cec_polling:
				; if(T)
				brtc done
					ldi state, IDLE

					ldi tmp, 1
					bst srcdst, 3 ; T = srcdst&0b1000
					andi srcdst, 0b0111

					; AVR doesn't have a binary lsl
					taken_bit_index:
						lsl tmp
						dec srcdst
						brne taken_bit_index

					; if(T >= 8)
					brts cec_poll_hi
					cec_poll_lo:
						or taken_lo, tmp
						DONE
					
					; else
					cec_poll_hi:
						or taken_hi, tmp
						DONE
			
			; else
			cec_notpolling:
				inc nbits

				; if(nbits >= 8)
				cpi nbits, 8
				brlt cec_eom
				cec_still_reading:
					lsl data
					; Note: T is still the most recent bit.
					;  It's destroyed in cec_polling, but
					;  that jumps to done
					brtc cec_push_0
						sbr data, 1
					cec_push_0:

					cpi nbits, 8
					brne done
						sbr gbf, ACK
						DONE

				; else
				cec_eom:
					ldi nbits, 0

					; if(!T)
					brts cec_check_who
						ldi state, IDLE
						DONE
					
					; else if(state == WHO)
					cec_check_who:
					cpi state, WHO
					brne cec_read_data
						mov srcdst, data

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
								; We own this address
								sbr gbf, ACK
								DONE
							
							; else
							cec_notme:
								; Read ACK response
								ldi state, POLL
								DONE
						; else
						cec_notpoll:
							; Note: data is needed to calculate the last
							;  if statement, so this andi can't be moved
							;  outside
							; if((data&0x0f) == cec_addr)
							andi data, 0x0f
							ldi state, DATA
							ldi it_lo, 0
							DONE
					
					; else
					cec_read_data:
						st it+, data
						DONE

		; else
		cec_falling:
			; if(reading && gbf.ACK)
			sbrc gbf, RW
			sbrs gbf, ACK ; RW=1
			rjmp done
				; Master requires ACK, send logical 1
				HOLD CEC
				
				ldi tmp, 0
				out COUNTER, tmp
				
				ldi tmp, JIFFY_1_LO
				out TIMEOUT, tmp

				; enable_timer()
				ldi tmp, 0b101
				out TIMER, tmp

				DONE

	sda_change:
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
				ldi nbits, 0
				ldi it_lo, 0
				ldi state, WHO

				DONE