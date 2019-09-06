#include "common.S"

; SCL change
__vector_5:
__int0:
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
			sbrc gbf, ACK
			rjmp done
				; Clear ACK regardless
				cbr gbf, 1<<ACK

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
			
			; data |= PIN(SDA)
			sbic PINB, SDA
			ori data, 1

			; Finished reading the packet, process it			
			; if(--dec == 0)
			dec nbits
			breq done ; rjmp if dec nbits != 0
				ldi nbits, 8 ; nbits = 8
				; if(state == WHO)
				cpi state, WHO
				brne i2c_process_data
				i2c_process_who:
					bst data, 0 ; T = datat&1
					lsr data ; data >>= 1

					; if(data == I2C_ADDR)
					cpi data, I2C_ADDR
					brne i2c_notme
						bld gbf, RW ; gbf.RW = T
						ldi state, DATA ; state = DATA
						DONE
					; else
					i2c_notme:
						ldi state, IDLE ; state = IDLE
						DONE
				
				; else
				i2c_process_data:
					st it+, data ; *it++ = data

					; if(it >= 16)
					cpi it_lo, 16
					brlt done
						ldi it_lo, 1 ; it = 1

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
			sbrc gbf, ACK
			rjmp done
				FREE SDA
				cbr gbf, ACK
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
			brne done ; Z = 0, rjmp int0_done if dec nbits != 0
				ld data, it+ ; data = *it++
				ldi nbits, 8 ; nbits = 8

				; if(it < 16)
				cpi it_lo, 16
				brge i2c_read_overflow
					HOLD SDA
					sbr gbf, ACK
					DONE
				
				; else
				i2c_read_overflow:
					ldi state, IDLE
					DONE