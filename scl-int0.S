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
	if_state IDLE, done
	
	if_low SCL, scl_falling
	scl_rising:
		; if(writing) / if(!reading)
		if_set RW, scl_rise_read
		scl_rise_write:
			; if(gbf.ACK)
			if_unset ACK, done
				clear_flag ACK
				; Write+ACK means SDA is free
				; if(!PIN(SDA))
				sbis PINB, SDA
				; IDLE + DONE is such a common pattern, and this
				;  is the one place where it can't be broken up
				ignore_rest:
					; Master sent NAK, idle
					ldi state, IDLE
				DONE
		
		; else: if(reading) / if(!writing)
		scl_rise_read:
			; Nothing to do if read && ack
			if_set ACK, done
			
			in tmp, PINB
			bst tmp, SDA
			rcall push_bit
			; if(byte boundary)
			brne done
				; switch(state)
				if_state DATA, i2c_proc_data
				if_state WHO, i2c_proc_who
				if_state CMD, i2c_proc_cmd
				DONE

				i2c_proc_data:
					rcall push_byte
					; would overflow, stop reading
					breq ignore_rest
					DONE

				i2c_proc_who:
					 bst data, 0 ; T = datat&1
					 lsr data ; data >>= 1
 
					 ; if(data == I2C_ADDR)
					cpi data, I2C_ADDR
					brne ignore_rest
					i2c_isme:
						bld gbf, RW ; gbf.RW = T
						ldi state, CMD
						DONE

				i2c_proc_cmd:
					; tmp = HIGH(data)
					mov tmp, data
					swap tmp
					andi tmp, 0x0f
					; data = LOW(data)
					andi data, 0x0f

					; switch(data)
					cpi data, RW_BUFFER
						; No preparation needed
						DONE
					cpi data, LOAD_TAKEN
						breq load_taken
					cpi data, CEC_SEND
						breq cec_send
					cpi data, SET_ADDR
						breq set_addr
					cpi data, TOGGLE_MON
						breq toggle_mon
					cpi data, TOGGLE_DEBUG
						breq toggle_debug
					DONE

					; Load the taken variable into the message buffer to be read
					load_taken:
						ldi length, 2
						sts message + 0, taken_hi
						sts message + 1, taken_lo
						ignore_rest_1:
						rjmp ignore_rest
					
					; Write whatever's in the message buffer to the CEC bus
					cec_send:
						clear_flag I2CEC
						; Immediately wait for arbitration
						ldi state, WAIT
						DONE
					
					; Set the CEC address
					set_addr:
						mov cec_addr, tmp
						rjmp ignore_rest

					; Toggle monitor mode, which reads all messages on the CEC
					;  bus into the buffer to be read periodically
					toggle_mon:
						ldi tmp, 1<<MONITOR
						eor gbf, tmp
						rjmp ignore_rest
					
					; Toggle debug mode, no use atm
					toggle_debug:
						ldi tmp, 1<<DEBUG
						eor gbf, tmp
						rjmp ignore_rest

	scl_falling:
		; On falling edge,
		;  (if reading and waiting for ack)
		;   hold for ack
		;  (if writing)
		;   free/hold for bit

		; if(reading) / if(!writing)
		if_unset RW, scl_fall_write
		scl_fall_read:
			if_unset ACK, done
				clear_flag ACK
				HOLD SDA
				DONE

		; else
		scl_fall_write:
			rcall get_next_bit
			brts scl_write_0
				HOLD SDA
			scl_write_0: 
				/* FREE SDA */
			
			; if read would overflow, IDLE
			brge ignore_rest_1
				set_flag ACK
				DONE
				