#include "global.h"

void i2c_read_bit() {
	//set_bit(PORTB, CEC);
	await_low(SCL);
	disable_i2c();
	
	await_high(SCL);
	enable_i2c();
	//clr_bit(PORTB, CEC);
	bst(PINB, SDA);
}

/**
 * This doesn't release the bus at the end so we don't change the bus
 *  state unnecessarily. START and STOP will FREE regardless.
**/
void i2c_write_bit() {
	await_low(SCL);
	disable_i2c();
	
	if_T() FREE(SDA);
	else HOLD(SDA);
	
	await_high(SCL);
	enable_i2c();
}

/**
 * The only way ATtiny10 is able to process fast enough for i2c is
 *  by processing while SCL is high. ACK is a special case because we
 *  expect that it might be followed by a START/STOP condition, so it
 *  needs to FREE(SDA) after SCL is low to let the master send those.
 * Naively, we'd just do this after every ACK, but this only gives
 *  about ~20 cycles before SCL goes high again. Instead, we split
 *  ACK into two stages - writing a logic 0 bit, and freeing the bus.
 *  This way, we can do as much processing as we need (and probably
 *  go past when SCL goes low on its own) then leisurely hand the bus
 *  back to master.
**/
void i2c_free_bus() {
	await_low(SCL);
	FREE(SDA);
	enable_i2c();
}

void i2c_read_byte() {
	register uint8_t nbits asm("22") = 8;
	
	// Data is completely overwritten
	//data = 0;
	
	do {
		i2c_read_bit();
		lsl(data);
		bld(data, 0);
	} while(--nbits);
}

void i2c_write_byte() {
	register uint8_t nbits asm("22") = 8;
	do {
		bst(data, 7);
		lsl(data);
		i2c_write_bit();
	} while(--nbits);
	
	i2c_free_bus();
	
	// Read the ACK bit
	i2c_read_bit();
}

// Note: The ATtiny10 is just barely fast enough to handle i2c, so
//  starting the code to read/write it needs to be as fast as possible
//  or it will lose synchronization and produce weird bugs.
ISR(PCINT0_vect, ISR_NAKED) {
	// This is handled in the IVT
	//if(!PIN(SCL)) return
	
	if(get_flag(FLAG_NEST)) {
		// Unwind the stack so reti goes to the original PC
		SPL = STACK_UNWIND;
	}
	
	set_flag(FLAG_NEST);
	
	disable_cec();
	sei();
	
	if(!PIN(SDA)) {
		/* START */
		
		// Address
		i2c_read_byte();
		bst(data, 0); // T = RW
		bld(flags, FLAG_RW); // flags.rw = T
		lsr(data);
		
	#if I2C_ADDR >= I2C_10BIT(0)
		// Upper 7 bits (5-bit prefix and 2 bits of 10)
		if(data == (hi8(I2C_ADDR)>>1)) {
			clt();
			i2c_write_bit();
			i2c_free_bus();
			i2c_read_byte(); // await_low repeated, fix?
			
			// Lower 8 bits
			if(data != lo8(I2C_ADDR)) {
				goto nack;
			}
		}
		else {
			goto nack;
		}
	#else
		if(data != I2C_ADDR) goto nack;
	#endif
		clt();
		i2c_write_bit(); // ACK
		// T = flags.rw
		bst(flags, FLAG_RW);
		if_T() {
			// Master read
			
			uint8_t* it;
			
			// Optimized branching out of order because it was taking
			//  too long to start writing and desynchronizing
			if(reg >= REG_CEC) {
				if(reg < REG_CEC + BUFFER_SIZE) {
				reg_cec:
					it = &buffer[reg - REG_CEC];
				#ifdef DIRTY
					// Any reads of CEC buffer clear the dirty signal
					clr_bit(PORTB, DIRTY);
				#endif
					do {
						//data = *it++;
						asm("ld %0, %a1+\n" : "+r"(data), "+e"(it));
						rcall(update);
					} while(++reg < REG_CEC + BUFFER_SIZE);
				}
				goto nack;
			}
			else if(reg < REG_ID + IDENT_SIZE) {
				it = (uint8_t*)&IDENT_STR[reg - REG_ID];
				
				do {
					//data = *it++;
					asm("ld %0, %a1+\n" : "+r"(data), "+e"(it));
					rcall(update);
				} while(reg < REG_ADDR);
				
				goto reg_addr;
			}
			else {
				if(reg <= REG_TAKEN_HI) {
					if(reg == REG_ADDR) {
					reg_addr:
						data = cec_addr;
						rcall(update);
						goto reg_taken_hi;
					}
					else {
					reg_taken_hi:
						data = hi8(taken);
						rcall(update);
						goto reg_taken_lo;
					}
				}
				else {
					if(reg == REG_TAKEN_LO) {
					reg_taken_lo:
						data = lo8(taken);
						rcall(update);
						goto reg_length;
					}
					else {
						reg_length:
						data = length;
						rcall(update);
						goto reg_cec;
					}
				}
			}
			
			unreachable();
		}
		else {
			// Master write
			
			// Register
			i2c_free_bus();
			i2c_read_byte();
			
			// NACK registers we have no data for
			if(data >= REG_CEC + BUFFER_SIZE) goto nack;
			
			reg = data;
			
			clt();
			i2c_write_bit();
			
			// Continue reading, assuming this is just master write
			//  If it was writing a register to be read, this
			//  interrupt will be restarted by a START condition
			if(reg == REG_ADDR) {
				i2c_free_bus();
				i2c_read_byte();
				clt();
				i2c_write_bit();
				cec_addr = data;
				++reg;
			}
			// Writes should only start at buffer[0]
			else if(reg == REG_CEC) {
				uint8_t* it = &buffer[0];
				length = 0;
				
				// Note: reg unmodified so next read is response
				do {
					i2c_free_bus();
					i2c_read_byte();
					// ACK
					clt();
					i2c_write_bit();
					//*it++ = data;
					asm("st %a0+, %1\n" : "+e"(it), "+r"(data));
					set_flag(FLAG_CEC);
				} while(++length < BUFFER_SIZE);
			}
			
			i2c_free_bus();
		}
	}
	else {
		/* STOP */
	}
	
nack:
	enable_cec();
	clr_flag(FLAG_NEST);
	reti();

			
// Every register uses this, so put it in one place
//  to avoid DRY mistakes and make smaller code
update:
	++reg; // Keep track in case of START or STOP
	i2c_free_bus();
	i2c_write_byte();
	if_T() {
		// Pop the return address (2 bytes) before nack
		register uint8_t t;
		asm volatile("pop %0\npop %0\n" : "=&r"(t));
		goto nack;
	}
	else {
		ret();
	}
}