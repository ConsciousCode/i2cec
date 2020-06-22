#include "common.hpp"

#include <avr/wdt.h>
#include <avr/sleep.h>
#include <avr/power.h>
#include <util/delay_basic.h>

void resume_next_int() {
	sei();
	sleep_cpu();
}

void await_next_int() {
	restart_timer();
	resume_next_int();
}

void _cec_rw_common() {
	await_next_int();
	
	FREE(CEC);
	
	// If CEC is still low, arbitration was lost
	bst(PINB, CEC);
	
	set_timeout_b(TICKS_BIT);
	resume_next_int();
}

void _cec_read_bit() {
	set_timeout_b(TICKS_SAMP);
	
	_cec_rw_common();
}

void _cec_write_bit() {
	if(T) {
		set_timeout_b(TICKS_1_LO);
	}
	else {
		set_timeout_b(TICKS_0_LO);
	}
	
	HOLD(CEC);
	
	_cec_rw_common();
}

void cec_write() {
	for(;;) {
		// Length must be copied just in case we lose
		//  arbitration halfway through.
		Register<23> len;
		
		// Try to write START
		HOLD(CEC);
		set_timeout_b(TICKS_START_LO);
		await_next_int();
		//cli();
		
		FREE(CEC);
		
		if(PIN(CEC)) {
			goto lost_arbitration;
		}
		
		set_timeout_b(TICKS_START);
		resume_next_int();
		//cli();
		
		Z = &msg.payload[0];
		len = length;
		
		do {
			//volatile register byte nbits asm("25");
			Register<24> data = *Z++;
			
			//nbits = 8;
			repeat(8) {
				T = data[7];
				data <<= 1;
				_cec_write_bit();
				if(!T) goto lost_arbitration;
			}
			
			// Write EOM bit
			T = (--len != 0);
			_cec_write_bit();
			if(!T) goto lost_arbitration;
			
			// Break early if the recipient sends NACK
			_cec_read_bit();
			if(T) break;
		} while(len);
		
		break;
		
		// Another device is using the bus, retry after a delay
		lost_arbitration:
			set_timeout_b(TICKS_BIT*3);
			await_next_int();
	}
	
	disable_tim0_compb();
}

ISR(INT0_vect, ISR_NAKED) {
	// Reused interrupt to wake from sleep. Use a normal return to
	//  keep the interrupt enable off
	if(flags.nest) {
		return;
	}
	// Reuse the interrupt for rising edge detection
	flags.nest = true;
	
	// Disable i2c while we process CEC
	disable_i2c();
	
	// Detect rising edge for START condition
	set_int0_mode(RISE);
	
	// Set a timeout to break out of CEC if it takes too long
	set_timeout_a(TICKS_START);
	enable_tim0_compa();
	await_next_int();
	//cli();
	
	// Right now, only int0 and tim0_compa are enabled. tim0_compa
	//  will cancel CEC processing, int0 will resume here.
	
	// Rest of the bits are processed by timing and sync'd by
	//  falling edge
	set_int0_mode(FALL);
	
	// If false, START condition failed
	if(TCNT0 >= TICKSHOLD_START_LO - TICKS_E) {
		byte* it asm("Z") = &buffer[0];
		
		// Cancel CEC if a bit takes too long
		set_timeout_a(TICKS_BIT*3/2);
		
		flags.who = false;
		
		do {
			byte nbits = 8;
			byte data = 0;
			
			//enable_int0();
			do {
				// Wait for next falling edge
				await_next_int();
				
				disable_int0();
				_cec_read_bit();
				data <<= 1;
				bld(data, 0);
				enable_int0();
			} while(--nbits);
			
			// Await falling edge
			await_next_int();
			
			disable_int0();
			_cec_read_bit(); // T = EOM
			
			if(!flags.who) {
				// Record the sender
				taken_vec |= _BV(hi4(data));
				
				// Record ping'd addresses
				brtc(not_ping);
				ping:
					taken_vec |= _BV(lo4(data));
				not_ping:
				
				if(data == CEC_DEFAULT) {
					
				}
				else if(data == cec_addr) {
					// Mine = ACK is our responsibility
					flags.mine = true;
				}
				else if(flags.monitor) {
					
				}
				else {
					break;
				}
				
				flags.who = true;
			}
			
			brtc(no_eom);
				flags.eom = true;
			
			no_eom:
			
			stz_inc(data);
			
			if(flags.mine) {
				set();
				_cec_write_bit();
			}
			else {
				_cec_read_bit();
				brts(got_ack);
				break;
			}
			
			got_ack:
			if(flags.eom) {
				break;
			}
			
			enable_int0();
		} while(++length <= 16);
	}
	
	flags.who = false;
	flags.mine = false;
	flags.eom = false;
	flags.nest = false;
	disable_tim0_compa();
	enable_i2c();
	
	reti();
}