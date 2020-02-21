#include "common.S"

/**
 * The PCINT0 is used for CEC read events and the i2c
 *  START/STOP conditions, which occur when SDA changes
 *  while SCL is high.
**/

__vector_2:
__pcint0:
	// We don't need to check for SDA/CEC change unless
	//  we're reading, write+ACK or read+!ACK
	mov tmp, gbf
	lsr tmp
	eor tmp, gbf
	sbis tmp, RW // skip if RW^ACK
	rjmp done // Must be writing to the bus, exit

	// Set up for determining rising/falling edge
	in tmp, PINB
	eor tmp, gbf
	// Flip the appropriate gbf bits
	andi tmp, (1<<OLD_CEC)|(1<<OLD_SDA)
	eor gbf, tmp // set gbf.old to pin.cur

	// If we're in idle, listen to either bus
	cpi state, IDLE
	brne check_bus
	
	// assert tmp = old^new
	sbrs tmp, CEC // CEC is set so CEC is the one that changed
	rjmp check_sda
	rjmp check_cec

	// ...otherwise, only need to pay attention to the bus we're on
	check_bus:
		if_set I2CEC, check_sda

	check_cec:
		// Early exit if it wasn't a change on CEC
		sbrs tmp, CEC
			DONE
		
		if_low CEC, cec_falling
		cec_rising:
			in tmp, COUNTER

			// if(COUNTER >= START_LO - E)
			cpi tmp, JIFFY_START_LO - JIFFY_E
				brge cec_start
			// else if(COUNTER >= ZERO_LO - E)
			cpi tmp, JIFFY_0_LO - JIFFY_E
				brge cec_check_0
			// else if(COUNTER >= ONE_LO - E)
			cpi tmp, JIFFY_1_LO - JIFFY_E
				brge cec_check_1
			// else
				DONE

			cec_start:
				// START
				clear_flag I2CEC
				if_clear MONITOR, no_monitor
					ldi nbits, 8
					ldi it_lo, 0
					ldi length, 0

				no_monitor:
					ldi state, WHO
					ldi nbits, 8
					DONE
			
			cec_check_0:
				clt // T = 0
				rjmp cec_bit
			
			cec_check_1:
				set // T = 1
			
			cec_bit:
			
			if_state EOM, cec_proc_eom

			rcall push_bit
			brne done

			// We passed the byte boundary, process it

			sbic gbf, MONITOR
				rcall push_byte

			cec_process:
				if_state DATA, cec_proc_data
				if_state WHO, cec_proc_who
				DONE

				cec_proc_eom:
					brts ignore_rest0
					cec_eom_cont:
						ldi state, DATA
						set_flag ACK
						DONE

				cec_proc_data:
					rcall push_byte
					brlt done
					#ifdef DIRTY_PIN
						sbi DIRTY_PIN
					#endif
						ignore_rest0:
							ldi state, IDLE
							DONE

				cec_proc_who:
					// Indicates a POLL message
					// if(high(data) == low(data))
					mov tmp, data
					swap tmp
					cp tmp, data
					brne cec_notpoll
					cec_ispoll:
						// if((data&0x0f) == cec_addr)
						andi data, 0x0f
						cp data, cec_addr
						brne cec_notme
						cec_me:
							// Still need the EOM
							ldi state, EOM
							// We own this address, ACK
							set_flag ACK
							DONE
						
						// else
						cec_notme:
							// We only need to record the address now, no
							//  need to wait for the ACK because a NAK
							//  implies the inciting device took the address
							ldi state, IDLE

							// AVR doesn't have a variable lsl instruction
							///// {build bit}
								ldi tmp, 1
								// No native 16 bit support, store it in T
								bst data, 3 // T = data&0b1000
								cbr data, 3
								// Jump immediately to the condition, use
								//  the Z flag from cbr
								rjmp build_taken_bit_cond
								build_taken_bit:
									lsl tmp // tmp <<= 1
									dec data // while(--data)
									build_taken_bit_cond:
									brne build_taken_bit
							///// {/build bit}

							brts cec_who_hi
							cec_who_lo:
								or taken_lo, tmp
								DONE
							cec_who_hi:
								or taken_hi, tmp
								DONE
					// else
					cec_notpoll:
						// if(data&0x0f == cec_addr)
						andi data, 0x0f
						cp data, cec_addr
						brne done
							ldi state, EOM
							set_flag ACK

							// Monitor mode already set up it
							if_set MONITOR done
								ldi it_lo, message + 1
								ldi length, 1
								swap tmp
								sts message, tmp
						DONE
				
		// else
		cec_falling:
			// if(reading && gbf.ACK)
			sbrc gbf, RW
			sbrs gbf, ACK // RW=1
			rjmp done
				// Master requires ACK, send logical 1
				HOLD CEC
				
				clear_timer
				set_timeout JIFFY_1_LO
				enable_timer
				DONE

	check_sda:
		// assert tmp = old^new
		// Early exit if it wasn't a change on SDA
		sbrs tmp, SDA
			DONE

		// Check for START/STOP condition, which can only
		//  happen if SDA changes while SCL is high
		if_low SCL, done
			// if(PIN(SDA))
			if_low SDA, ignore_rest0 // => STOP
			sda_falling:
				// START
			#ifdef DIRTY_PIN
				cbi DIRTY_PIN
			#endif
				set_flag I2CEC // i2c mode
				set_flag RW // read mode
				clear_flag ACK // should be 0, do for sanity
				ldi state, WHO
				ldi nbits, 8 // expecting 8 bits
				ldi length, 0 // buffer is cleared
				ldi it_lo, 0 // reset buffer iterator
				DONE