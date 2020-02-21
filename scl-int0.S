#include "common.S"

/**
 * The INT0 interrupt monitors edges on SCL. Reads occur
 *  on the rising edge, writes on the falling edge (if
 *  in the appropriate mode)
**/

__vector_5:
__int0:
	// We can safely ignore the clock if we're idling -
	//  the START condition doesn't require an SCL edge
	if_state IDLE, done
	
	if_low SCL, scl_falling
	scl_rising:
		// if(writing) / if(!reading)
		if_set RW, scl_rise_read
		scl_rise_write:
			// Device id subprotocol handle writing the id
			cpi state, DEVID
			brne write_check_ack
				in tmp, PINB
				bst tmp, SDA // T = SDA
				rcall push_bit
				brne done
					ldi tmp, ((DEVID_DATA)>>2)&0xff
					sts message + 0, tmp
					ldi tmp, ((DEVID_DATA)>>1)&0xff
					sts message + 1, tmp
					ldi tmp, ((DEVID_DATA)>>0)&0xff
					sts message + 2, tmp
					ldi length, 3
					ldi state, DATA
					DONE

			write_check_ack:
			// if(gbf.ACK)
			if_clear ACK, done
				clear_flag ACK
				// Write+ACK means SDA is free
				// if(!PIN(SDA))
				sbis PINB, SDA
				// IDLE + DONE is such a common pattern, and this
				//  is the one place where it can't be broken up
				//  so we'll reuse this for later
				ignore_rest:
					// Master sent NAK, idle
					ldi state, IDLE
				DONE
		
		// else: if(reading) / if(!writing)
		scl_rise_read:
			// Nothing to do if read && ack
			if_set ACK, done
			
			in tmp, PINB
			bst tmp, SDA // T = SDA
			rcall push_bit
			// if(byte boundary)
			brne done
				// switch(state)
				if_state WHO, i2c_proc_who

				// Other than WHO, we always want to send ACK
				set_flag ACK

				if_state DATA, i2c_proc_data
				if_state EXEC, i2c_proc_exec
				if_state DEVID, i2c_proc_devid
				if_state CMD, i2c_proc_cmd
				ldi state, IDLE // Sanity, handle invalid states
				DONE

				i2c_proc_who:
					bst data, 0 // T = data[bit 0]
					lsr data // data >>= 1
 
					 // if(data == I2C_ADDR)
					cpi data, I2C_ADDR
					brne i2c_isnotme
					i2c_isme:
						bld gbf, RW // gbf.RW = T
						set_flag ACK // Send ACK
						ldi state, CMD
						DONE
					
					i2c_isnotme:
						cpi data, DEVID
						brne ignore_rest
						brts ignore_rest // Must be write mode
						
						// Stay in read mode to trigger i2c_proc_devid
						set_flag ACK // Send ACK
						ldi state, DEVID
						DONE

				// Read until we would overflow
				i2c_proc_data:
					rcall push_byte
					breq ignore_rest
					DONE
			
				// Commands with side effects
				i2c_proc_exec:
					// switch(cmd)
					if_cmd SET_LENGTH, exec_set_length
					if_cmd RESET, exec_reset
					if_cmd CEC_SEND, exec_cec_send
					if_cmd SET_ADDR, exec_set_addr
					if_cmd TOGGLE_MON, exec_toggle_mon
					if_cmd TOGGLE_DEBUG, exec_toggle_debug
					
					// Enable reading all RAM for debugging
					exec_set_length:
						andi data, 0x0f
						mov length, data
						rjmp ignore_rest
					
					exec_reset:
						cli
						// Set the watch dog enable bit with minimum prescaling
						ldi tmp, 0b00001000
						out WDTCSR, tmp
						// Return from interrupt jumps to the infinite loop in main,
						//  which now can't be interrupted until the watchdog resets
						reti
					
					// Write whatever's in the message buffer to the CEC bus
					exec_cec_send:
						clear_flag I2CEC
						// Immediately wait for arbitration
						ldi state, WAIT
						DONE
					
					// Set the CEC address
					exec_set_addr:
						andi data, 0x0f
						mov cec_addr, data
						rjmp ignore_rest

					// Toggle monitor mode, which reads all messages on the CEC
					//  bus into the buffer to be read periodically
					exec_toggle_mon:
						ldi tmp, 1<<MONITOR
						eor gbf, tmp
						rjmp ignore_rest
					
					// Toggle debug mode, no use atm
					exec_toggle_debug:
						ldi tmp, 1<<DEBUG
						eor gbf, tmp
						rjmp ignore_rest

				i2c_proc_devid:
					cpi data, I2C_ADDR
					brne ignore_rest2
					clear_flag RW // write mode
					DONE // Now we wait for DEVID,w
				
				i2c_proc_cmd:
					mov cmd, data

					// if MSB is set, we need a validation byte first
					sbis cmd, 7
					rjmp i2c_load
						ldi state, EXEC
						DONE
					i2c_load:
						if_cmd NOP, ignore_rest2

						//> length set by load
						if_cmd LOAD_ID, i2c_load_id
						if_cmd LOAD_ADDR, i2c_load_addr
						
						// All of these have at least length=1
						mov tmp, length
						ldi length, 1
						if_cmd LOAD_LENGTH, i2c_load_length
						if_cmd LOAD_GBF, i2c_load_gbf
						if_cmd LOAD_I2C, i2c_load_i2c
						if_cmd LOAD_CEC, i2c_load_cec

						// At least length=2
						inc length
						if_cmd LOAD_TAKEN, i2c_load_taken

						// Ignore invalid loads
						mov length, tmp
						rjmp ignore_rest2

						// Unreachable segment, put the info here
						ID_VAL: .ascii VERSION
						.equ ID_LEN, (.-ID_VAL)

						// Emit the readonly firmware identity
						i2c_load_id:
							ldi length, ID_LEN
							ldi it_lo, message
							ldi Z_lo, lo8(ID_VAL)
							ldi Z_hi, hi8(ID_VAL)
							i2cec_id_load:
								ld tmp, it+
								st Z+, tmp
								dec length
								brne i2cec_id_load
							ldi length, ID_LEN
							rjmp ignore_rest2
						
						// Move `length` bytes into buffer from loaded address
						//  Assumes buffer has 2 bytes loaded for address
						i2c_load_addr:
							lds Z_hi, message + 0
							lds Z_lo, message + 1
							ldi it_lo, message
							do_load_addr:
								ld tmp, Z+
								st it+, tmp
								dec length
								breq do_load_addr
							
							rjmp ignore_rest2
						
						i2c_load_length:
							sts message, length
							rjmp ignore_rest2
						
						i2c_load_gbf:
							sts message, gbf
							rjmp ignore_rest2
						
						i2c_load_i2c:
							ldi tmp, I2C_ADDR
							sts message, tmp
							rjmp ignore_rest2
						
						i2c_load_cec:
							sts message, cec_addr
							rjmp ignore_rest2

						// Load the vector of taken CEC addresses
						i2c_load_taken:
							sts message + 0, taken_hi
							sts message + 1, taken_lo
							ignore_rest2:
								ldi state, IDLE
								DONE

	scl_falling:
		// On falling edge,
		//  (if reading and need to ack)
		//   hold for ack
		//  (if writing)
		//   write bit to SDA

		// if(reading) / if(!writing)
		if_clear RW, scl_fall_write
		scl_fall_read:
			if_clear ACK, done
			// else
				clear_flag ACK
				HOLD SDA
				DONE

		// else
		scl_fall_write:
			rcall next_bit
			brtc sda_write_0
				HOLD SDA
			sda_write_0:
				// SDA is already free because we had to read it
				/* FREE SDA */
			
			// if read would overflow, IDLE
			brne ignore_rest2
			// else
				set_flag ACK // Expect ACK from master
				DONE
				