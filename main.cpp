#include "common.h"

#include <avr/interrupt.h>
#include <avr/sfr_defs.h>
#include <avr/wdt.h>
#include <avr/sleep.h>
#include <avr/power.h>
#include <util/delay_basic.h>

#define nomangle extern "C"

/**
 * avr-gcc's calling convention passes and returns mostly through
 *  registers, but even this is too wasteful. To use custom
 *  calling conventions, these are split into two subroutines:
 *  an implementation and a stub to set up the call
**/

// Load memory at address into the buffer
nomangle void _memload() {
	byte len = length;
	byte* it asm("Y") = &buffer[0];
	byte t;
	do {
		asm("ld %0, Y+" :"=r"(t));
		stz_inc(t);
	} while(--len);
}
inline void memload(byte* src) {
	byte* z asm("Z") = src;
	_memload();
}

// Read the next i2c bit
nomangle void _i2c_read_bit() {
	sei();
	await_low(SCL);
	cli();
	await_high(SCL);
	bst(PINB, SDA);
}
inline bool i2c_read_bit() {
	_i2c_read_bit();
	bool b;
	bld(b, 0);
	return b;
}

// Write an i2c bit
nomangle void _i2c_write_bit() {
	brts(skip_hold);
		HOLD(SDA);
	skip_hold:
	await_high(SCL);
	await_low(SCL);
	FREE(SDA);
}
inline void i2c_write_bit(bool b) {
	bst(b, 0);
	_i2c_write_bit();
}

// Read the next CEC bit
nomangle void _cec_read_bit() {
	await_low(CEC);
	TCNT0L = 0;
	await_high(CEC);
	byte t = TCNT0L;
	asm volatile(
		"cpi %0, " M(JIFFY_1_LO + JIFFY_E) ::"r"(t) : "cc"
	);
}
inline bool cec_read_bit() {
	_cec_read_bit();
	asm goto("brlt %l0" :::: ret_true);
		return false;
	ret_true:
		return true;
}

// Write a CEC bit
nomangle void _cec_write_bit() {
	constexpr int cycles = 4;
	
	byte count = JIFFY_BIT;
	byte comp = JIFFY_1_LO;
	brts(wait_lo);
		comp = JIFFY_0_LO/cycles;
	wait_lo:
	HOLD(CEC);
	asm volatile(R"(
		cec_loop_low:
			dec %0
			cp %0, %1
			brge cec_loop_low
	)" :"+r"(count) :"r"(count),"r"(comp));
	FREE(CEC);
	asm volatile(R"(
		cec_loop_high:
			dec %0
			nop ; for timing
			brne cec_loop_high
	)" : "+r"(count) :"r"(count));
}
inline void cec_write_bit(bool b) {
	bld(b, 0);
	_cec_write_bit();
}

// These have to be implemented in volatile assembly to ensure they
//  make efficient use of registers and don't need to push/pop
//  registers to the stack.

// Read the next i2c byte
__attribute__((naked)) byte i2c_read_byte() {
	// avr-gcc uses r17 as __zero_reg__ and fights tooth and nail
	//  to keep that definition. BUT, it'll be 0 by the end so we'll
	//  just... borrow it!
	asm volatile(R"(
		ldi 24, 0
		ldi 17, 8
		i2c_read_byte_loop:
			lsl 24
			rcall _i2c_read_bit
			bld 24, 0
			dec 17
			brne i2c_read_byte_loop
		ret
	)");
}

// Write a byte to i2c
__attribute__((naked)) void i2c_write_byte(byte data) {
	register byte dd asm("24") = data;
	asm volatile(R"(
		ldi 17, 8
		i2c_write_byte_loop:
			bst 24, 0
			rcall _i2c_write_bit
			lsr 24
			dec 17
			brne i2c_write_byte_loop
		ret
	)");
}

// Read the next CEC byte
__attribute__((naked)) byte cec_read_byte() {
	asm volatile(R"(
		ldi 24, 0
		ldi 17, 8
		cec_read_byte_loop:
			lsl 24
			rcall _cec_read_bit
			brge cec_read_byte_clear_bit
				sbr 24, 0
			cec_read_byte_clear_bit:
			dec 17
			brne cec_read_byte_loop
		ret
	)");
}

// Write a byte to CEC
__attribute__((naked)) void cec_write_byte(byte data) {
	register byte dd asm("24") = data;
	asm volatile(R"(
		ldi 17, 8
		cec_write_byte_loop:
			bst 24, 0
			rcall _cec_write_bit
			lsr 24
			dec 24
			brne cec_write_byte_loop
		ret
	)");
}

void cec_ack() {
	// Technically the same as writing a 0 bit, but we don't have to
	//  explicitly handle the HI portion.
	HOLD(CEC);
	_delay_loop_1(JIFFY_0_LO/3);
	FREE(CEC);
}

#define enable_cec() EIMSK = 1
#define disable_cec() EIMSK = 0

ISR(PCINT0_vect, ISR_NAKED) {
	// Keep nested interrupts only 1 deep
	if(flag_is_set(NEST)) {
		clear_flag(NEST);
		byte _unused;
		asm volatile("pop %0" : "=r"(_unused) :: "__SP_L__", "__SP_H__");
		// Continue processing as normal
		//  START will restart the reading process and
		//  STOP will end whatever was started
	}
	else if(!PIN(SCL)) {
		return;
	}
	
	// We don't want to process CEC interrupts while handling i2c
	disable_cec();
	
	// SCL is high and SDA changed, special bus condition START/STOP
	
	if(PIN(SDA)) {
		// START
		
		byte* it asm("Z") = &buffer[0];
		
		for(;;) {
			byte data = i2c_read_byte();
			
			if(state == WHO) {
				// T = data&1
				bst(data, 0);
				lsr(data);
				
				if(data != I2C_ADDR) {
					// NAK
					break;
				}
				
				// if(!T) goto ack
				// 0 = write, need to read more
				brtc(ack);
				
				// 1 = read, write buffer contents
				while(length) {
					dec(length);
					//ACK
					i2c_write_bit(0);
					i2c_write_byte(ldz_inc());
				}
				
				// NAK
				break;
			}
			else {
				stz_inc(data);
				inc(length);
				if(length >= 16 + 1) {
					state = CMD;
					
					// NAK
					break;
				}
			}
			
			ack: i2c_write_bit(0);
		}
	}
	else {
		// STOP
		if(state == DATA) {
			state = IDLE;
		} 
	}
	
	enable_cec();
	
	reti();
}

ISR(INT0_vect, ISR_NAKED) {
	//assert(PIN(CEC) == 0)
	
	// Expect a START condition
	TCNT0L = 0;
	await_high(CEC);
	if(TCNT0L < JIFFY_START_LO - JIFFY_E) return;
	
	byte* it asm("Z") = &buffer[0];
	
	do {
		byte data = cec_read_byte();
		
		//eom = cec_read_bit();
		{
			// load eom into T
			_cec_read_bit();
			byte t = SREG;
			bld(t, SREG_N); // T = N
		}
		
		if(state == WHO) {
			// Record the sender
			taken |= _BV(HI(data));
			
			if(LO(data) == CEC_DEFAULT) {
				// Nothing to do
			}
			else if(LO(data) == cec_addr) {
				set_flag(MINE);
			}
			else {
				// PING
				//if(eom)
				brtc(ping_end);
				{
					// Usually PING is for scouting possible addresses
					taken |= _BV(data&0x0f);
				}
				ping_end:
				
				// Not for us, only record if in monitor mode
				if(flag_is_clear(MONITOR)) {
					break;
				}
			}
			
			state = DATA;
		}
		
		stz_inc(data);
		if(++length >= 16) {
			break;
		}
		
		if(flag_is_set(MINE)) {
			cec_ack();
		}
		
		brtc(endloop);
	} while(1);//while(!eom);
	endloop:
	
	reti();
}

enum InterruptMode {
	IM_LOW = 0,
	IM_CHANGE = 1,
	IM_FALL = 2,
	IM_RISE = 3
};

enum SleepMode {
	SM_DISABLE = 0,
	SM_ENABLE = 1,
	
	SM_IDLE = 0b000<<1,
	SM_NOISE_REDUCE = 0b001<<1,
	SM_POWERDOWN = 0b010<<1,
	SM_STANDBY = 0b100<<1
};

inline void _init() {
	/// Setup all the I/O registers
	
	// External interrupt (INT0)
	EIMSK = 1;
	EICRA = IM_LOW;
	
	// Pin change interrupt (PCINT0)
	PCMSK = _BV(CEC);
	PCICR = 1; // Pin change interrupt enable
	
	// Pull-up enable
	PUEB = _BV(SDA) | _BV(CEC) | _BV(SCL);
	
	// Sleep mode
	SMCR = SM_IDLE | SM_ENABLE;

	// Clock prescaling factor 1 (8 MHz)
	clock_prescale_set(clock_div_1);

	// Set up pin change inerrupt
	DDRB = !_BV(CEC) | !_BV(SDA) | !_BV(SCL);
	
	// Disable unused modules and sleep
	
	DIDR0 = 0b1000; // Disable ADC3's digital buffer (unused)
	PRR = 0b10; // Disable ADC module
	
	taken = 0;
	length = 0;
	cec_addr = CEC_DEFAULT;
}

inline void _handle_action(byte cmd) {
	// Ignore action commands with no payload byte
	if(length < 2) return;
	
	switch(cmd) {
		case SET_LENGTH:
			length = LO(buffer[1]);
			break;
		
		case RESET:
			// No native reset, so run watchdog with tight loop
			wdt_enable(WDTO_15MS);
			for(;;) {}
			__builtin_unreachable();
		
		// Write the message buffer to the CEC bus
		case CEC_SEND: {
			byte* it asm("Z") = &buffer[1];
			do {
				cec_write_byte(ldz_inc());
				
				// Write EOM bit
				cec_write_bit(length == 1);
				
				// Break early if the recipient sends NAK
				if(cec_read_bit()) {
					length = 1;
				}
			} while(--length);
			break;
		}
		
		// Set the CEC address
		case SET_ADDR:
			cec_addr = LO(buffer[1]);
			break;
		
		// Toggle monitor mode, which reads all messages on the CEC
		//  bus into the buffer to be read periodically
		case TOGGLE_MON:
			gbf |= _BV(MONITOR);
			break;
	}
}

inline void _handle_load(byte cmd) {
	if(cmd&1) {
		switch(cmd) {
			case LOAD_LEN:
				buffer[0] = length;
				break;
			
			case LOAD_GBF:
				buffer[0] = gbf;
				break;
			
			case LOAD_I2C:
				buffer[0] = I2C_ADDR;
				break;
			
			case LOAD_CEC:
				buffer[0] = cec_addr;
				break;
		}
		length = 1;
	}
	else {
		switch(cmd) {
			case NOP: break;
			
			case LOAD_ID:
				length = (byte)(sizeof(VERSION));
				memload((byte*)VERSION);
				break;
			
			case LOAD_ADDR:
				// Assume length is already set
				memload((byte*)*((uint16_t*)buffer));
				break;
			
			case LOAD_TAKEN:
				buffer[0] = taken>>8;
				buffer[1] = taken&0xff;
				length = 2;
				break;
		}
	}
}

[[noreturn]] void main() {
__main:
	_init();
	
	for(;;) {
		state = IDLE;
		sei();
		
		do {
			// sleep at the top so we don't waste cycles rjmping after reti
			sleep_cpu();
			
			// Uncomment to disable command processing
			continue;
		
		// State is volatile and will change during interrupts
		} while(state != CMD);
		
		// Disable interrupts while processing commands
		cli();
		
		byte cmd = buffer[0];
		if(cmd & ACTION) {
			_handle_action(cmd);
		}
		else {
			_handle_load(cmd);
		}
	}
	
	__builtin_unreachable();
}
