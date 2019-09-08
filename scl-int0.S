#include "common.S"

/**
 * The INT0 interrupt monitors edges on SCL. Reads occur
 *  on the rising edge, writes on the falling edge (if
 *  in the appropriate mode)
**/

__vector_5:
__int0:
	; We can safely ignore the clock if we're idling -
	;  the START condition doesn't require an SCL edge

	; if(state == IDLE) return;
	cpi state, IDLE
	breq done
	
	; if(PIN(SCL))
	sbis PINB, SCL
	rjmp scl_falling
	scl_rising:
		; On rising edge,
		;  (if writing and waiting for ack)
		;   sample ack and either continue or quit
		;  (if reading)
		;   sample SDA
		;   handle received bits

		; if(writing) / if(!reading)
		sbrc gbf, RW
		rjmp scl_rise_read
		scl_rise_write:
			; if(gbf.ACK)
			sbrs gbf, ACK
			rjmp done
				cbr gbf, 1<<ACK
				; Write+ACK means SDA is free
				; if(!PIN(SDA))
				sbis PINB, SDA
					; Master sent NAK, idle
					ldi state, IDLE
				DONE
		
		; else
		scl_rise_read:
			; if(gbf.ACK) return
			; Nothing to do if read && ack
			sbic gbf, ACK
				rjmp done
			
			lsl data ; data <<= 1
			
			; Read+!ACK means SDA is free
			; data |= PIN(SDA)
			sbic PINB, SDA
			ori data, 1

			; Finished reading the packet, process it			
			; if(--dec == 0)
			dec nbits
			brne done ; rjmp if dec nbits != 0
				ldi nbits, 8
				; if(state == WHO)
				cpi state, WHO
				brne i2c_process_cmd
				i2c_process_who:
					bst data, 0 ; T = datat&1
					lsr data ; data >>= 1

					; if(data == I2C_ADDR)
					cpi data, I2C_ADDR
					brne i2c_notme
					i2c_isme:
						bld gbf, RW ; gbf.RW = T
						ldi state, CMD
						DONE
					; else
					i2c_notme:
						; IDLE implicitly ignores the bus
						;  until the next START condition
						ldi state, IDLE
						DONE
				; else if(state == CMD)
				i2c_process_cmd:
				cpi state, CMD
				brne i2c_process_data
					mov tmp, data
					swap tmp
					andi tmp, 0x0f
					andi data, 0x0f

					; RW_BUFFER
					cpi data, RW_BUFFER
					brne after_rw_buffer
						; No preparation needed
						DONE

					; LOAD_TAKEN
					after_rw_buffer:
					cpi data, LOAD_TAKEN
					brne after_load_taken
						ldi length, 2
						sts 0x00, taken_hi
						sts 0x01, taken_lo
						; Nullary op, ignore anything else
						ldi state, IDLE
						DONE
					
					; CEC_SEND
					after_load_taken:
					cpi data, CEC_SEND
					brne after_cec_send
						cbr gbf, I2CEC
						; Immediately go to wait for arbitration
						ldi state, WAIT
						DONE
					
					; SET_ADDR (set CEC address)
					after_cec_send:
					cpi data, SET_ADDR
					brne after_set_addr
						mov cec_addr, tmp
						ldi state, IDLE
						DONE

					; Unknown command, ignore it
					after_set_attr:
						ldi state, IDLE
						DONE

				; else
				i2c_process_data:
					st it+, data ; *it++ = data
					inc length

					; Stop when we would overflow the buffer
					; if(length >= 16)
					cpi length, 16
					brlt done
						ldi state, IDLE
						DONE

	scl_falling:
		; On falling edge,
		;  (if reading and waiting for ack)
		;   hold for ack
		;  (if writing)
		;   free/hold for bit

		; if(reading) / if(!writing)
		sbrs gbf, RW
		rjmp scl_fall_write
		scl_fall_read:
			; if(gbf.ACK)
			sbrs gbf, ACK
			rjmp done
				cbr gbf, ACK
				HOLD SDA
				DONE

		; else
		scl_fall_write:
			; Free/hold bus based on the msb
			sbrs data, 7
				FREE SDA
			sbrc data, 7
				HOLD SDA

			lsl data ; data <<= 1

			; Done with current byte
			; if(--nbits == 0)
			dec nbits
			brne done
				ld data, it+ ; data = *it++
				ldi nbits, 8

				; if(it < length)
				cp it_lo, length
				brge i2c_read_overflow
					; Send ACK
					sbr gbf, ACK
					HOLD SDA
					DONE
				
				; else
				i2c_read_overflow:
					; Implicit NAK
					ldi state, IDLE
					DONE