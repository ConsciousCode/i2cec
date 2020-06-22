#include "common.hpp"

#include <avr/sleep.h>
#include <avr/power.h>
#include <util/delay_basic.h>
#include <avr/pgmspace.h>

// Read the next i2c bit
void _i2c_read_bit() {
	await_low(SCL);
	disable_i2c();
	
	FREE(SDA);
	
	await_high(SCL);
	enable_i2c();
	
	T = PIN(SDA);
}

// Write an i2c bit
void _i2c_write_bit() {
	await_low(SCL);
	
	if(T) {
		FREE(SDA);
	}
	else {
		HOLD(SDA);
	}
	
	await_high(SCL);
	await_low(SCL);
}

Register<23> i2c_read_byte() {
	Register<23> data = 0;
	
	repeat(8) {
		_i2c_read_bit();
		data <<= 1;
		data[0] = T;
	}
	
	return data;
}

void i2c_write_byte(Register<23> data) {
	repeat(8) {
		T = data[7];
		data <<= 1;
		_i2c_write_bit();
	}
}

void i2c_write_ack() {
	// Write ACK
	disable_i2c();
	T = 0;
	_i2c_write_bit();
	enable_i2c();
}

void i2c_dump() {
	if(length) {
		i2c_write_ack();
		
		// 1 = read, write buffer contents
		
		do {
			i2c_write_byte(*Z++);
			_i2c_read_bit();
			if(T) break;
		} while(--length);
	}
}

void load_reg() {
	byte r = msg.reg;
	
	if(r == REG_CEC) {
		// Everything's already in the buffer, just check it's not
		//  non-CEC stuff
		if(!flags.cec) {
			length = 0;
		}
		
		disable_i2c();
		enable_tim0_compb();
		
		// Interrupts return immediately
		cec_write();
		enable_i2c();
	}
	else if(r <= REG_MAX) {
		if(r == REG_ID) {
			length = (byte)(sizeof(id_str));
			
			X = (byte*)id_str;
			Z = &msg.payload[0];
			
			Register<22> len = length;
			do {
				*Z++ = *X++;
			} while(--len);
		}
		else if(r == REG_ADDR) {
			if(length == 1) {
				msg.value = cec_addr;
			}
			else {
				cec_addr = msg.value;
			}
		}
		else if(r == REG_MONITOR) {
			if(length == 1) {
				msg.value = flags.monitor;
			}
			else {
				flags.monitor = msg.value;
			}
		}
		else if(r == REG_TAKEN) {
			if(length == 1) {
				msg.taken = taken_vec;
				length = 2;
			}
			else {
				taken_vec = msg.taken;
			}
		}
		else {
			__builtin_unreachable();
		}
	}
	else {
		/* invalid register, do nothing */
	}
}

ISR(PCINT0_vect, ISR_NAKED) {
	/*
	// This is handled in assembly in the IVT
	if(!PIN(SCL)) {
		reti();
	}
	*/
	
	// Nested interrupts need the stack to be unwound to main
	if(flags.nest) {
		SPL = RAMEND - 2;
		
		// Continue processing as normal
		//  START will restart the reading process and
		//  STOP will end whatever was started
		
		load_reg();
		
		// We don't want to process CEC interrupts while handling i2c
		disable_cec();
	}
	else {
		flags.nest = true;
	}
	
	// Disable pcint so it's not executed on sei()
	FREE(SDA);
	disable_i2c();
	
	sei();
	
	// SCL is high and SDA changed, special bus condition START/STOP
	
	if(!PIN(SDA)) {
		// START (hi -> lo while SCL hi)
		
		Z = &msg.buffer[0];
		
		flags.who = false;
		for(;;) {
			Register<23> data = i2c_read_byte();
			
			if(flags.who) {
				T = data[0];
				data >>= 1;
				
				if(data != I2C_ADDR) {
					// NACK
					break;
				}
				
				if(T) {
					i2c_dump();
					// NACK
					break;
				}
				else {
					flags.who = true;
					length = 0;
				}
			}
			else {
				*Z++ = data;
				if(++length >= 1 + BUFFER_SIZE) {
					break;
				}
			}
			
			i2c_write_ack();
		}
		FREE(SDA);
	}
	else {
		// STOP
	}
	
	enable_i2c();
	//enable_cec();
	flags.nest = false;
	
	reti();
}