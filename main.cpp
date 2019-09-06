/**
i2c interface:
* CMD <data>
  - 0x00 ping / pong
  - 0x01 reset
  - 0x02 (cmd [payload]) dump message to CEC
  - 0x03 read response
  - 0x04 get cec address
  - 0x05 read addresses
  - 0x06 get i2c address
**/

#include "config.h"

/*
 * Interoperation buffer between i2c and CEC. i2c can write to this, and
 *  subsequent reads will be based on the value of i2c_cmd. Conversely,
 *  this will also store the CEC messages directed at the device
*/
volatile static union {
	byte i2c_cmd;
	byte message[17];
};
volatile static uint16_t taken; // taken addresses

enum : byte {
	IDLE, START, WHO, EOM, STOP, WAIT, DATA, POLL
} state;

volatile byte srcdst;

volatile byte cec_addr;

volatile byte offset;
volatile byte length;
volatile byte data;
volatile byte nbits;

// General-purpose bitfield
volatile struct {
	bool _rw : 1;
	bool _bit : 1;
	bool _ack : 1;
	bool _lohi : 1;

	bool _old_sda : 1;
	bool _old_cec : 1;
} gbf;

#define rw (gbf._rw)
#define ack (gbf._ack)
#define lohi (gbf._lohi)
#define bit (gbf._bit)
#define old_sda (gbf._old_sda)
#define old_cec (gbf._old_cec)

#define OUT(p) (DDRB |= p)
#define IN(p) (DDRB &= ~p)

#define PIN(p) bit_is_set(PINB, p)
// All pins set as low out, changing to IN stops holding
#define HOLD(p) OUT(p)
#define FREE(p) IN(p)

#define enable_timer() (TCCR0B = 0b101)
#define disable_timer() (TCCR0B = 0)
#define set_timeout(x) (OCR0AL = x)

#define get_bit(b) (message[b>>3]&(1<<(8 - b&7)))
#define set_bit(b, v) (message[b>>3] = v<<(8 - b&7))

#define RETI() {reti(); __builtin_unreachable();}

ISR(TIM0_COMPA_vect) {
	// assert: i2c_cec == CEC
	// assert: rw == WRITE

	if(rw == READ) {
		FREE(CEC);
		ack = 0;
		disable_timer();
		goto done;
	}

	if(lohi == LO) {
		FREE(CEC);
		if(PIN(CEC)) {
			lohi = HI;
			set_timeout(state == WAIT? JIFFY_START : JIFFY_BIT);
		}
		else {
			goto bus_taken;
		}
	}
	else {
		if(PIN(CEC)) {
			if(ack) {
				ack = 0;
				disable_timer();
				goto done;
			}
			goto next_bit;
		}
		else {
			goto bus_taken;
		}
	}
	
	bus_taken:
		state = WAIT;
		set_timeout(JIFFY_BIT*3);
		goto done;
	
	next_bit:
		if(state == WAIT) {
			state = DATA;
			offset = 0;
			// No reason to go through hoops
			goto normal_bit;
		}
		if(offset%8 == 0) {
			if(ack) {
				ack = 0;
				state = EOM;
				bit = (offset < length);
			}
			else if(state == EOM) {
				if(offset < length) {
					state = DATA;
					goto normal_bit;
				}
				else {
					state = IDLE;
					disable_timer();
					goto done;
				}
			}
			else {
				// Try to transmit a 1 bit, ACK makes it 0
				bit = 1;
				ack = 1;
			}
		}
		else {
			normal_bit:
				bit = get_bit(offset);
		}
		lohi = LO;
		HOLD(CEC);
		set_timeout(bit? JIFFY_1_LO : JIFFY_0_LO);
	
	done: RETI();
}

// Respond to SDA or CEC change
ISR(PCINT0_vect) {
	// CEC change
	if(old_cec != PIN(CEC)) {
		old_cec = PIN(CEC);

		// Rising edge
		if(PIN(CEC)) {
			if(TCNT0L >= JIFFY_START_LO - JIFFY_E) {
				state = WHO;
				goto done;
			}
			else if(TCNT0L >= JIFFY_0_LO - JIFFY_E) {
				bit = 0;
			}
			else if(TCNT0L >= JIFFY_1_LO - JIFFY_E) {
				bit = 1;
			}
			else {
				// Too fast, ignore
				goto done;
			}

			if(state == POLL) {
				if(bit) {
					taken |= 1<<(srcdst&0x0f);
				}
			}

			++nbits;

			// Still reading
			if(nbits <= 8) {
				data <<= 1;
				data |= bit;

				if(nbits == 8) {
					ack = 1;
				}
			}
			else {
				nbits = 0;
				if(!bit) {
					state = IDLE;
				}
				else if(state == WHO) {
					srcdst = data;

					// hi_nibble == lo_nibble
					// Normal method is 6 instructions
					asm goto (
						"mov r28, %0\n"
						"swap r28\n"
						"cp r28, %0\n"
						"brne %l1"
						: /* No output */
						: "r" (data)
						: "cc", "r28"
						: notpoll
					); {
						// We own the address
						if((data&0x0f) == cec_addr) {
							ack = 1;
						}
						else {
							// Check for the poll response
							state = POLL;
						}
						goto done;
					}
					notpoll:
					if((data&0x0f) == cec_addr) {
						state = DATA;
						offset = 8;
					}
				}
				else {
					message[offset++] = data;	
				}
			}
		}
		// Falling edge
		else {
			if(rw == READ && ack) {
				// Pull cec low for the duration of a 0 bit
				HOLD(CEC);
				TCNT0L = 0;
				set_timeout(JIFFY_1_LO);
				enable_timer();
				goto done;
			}
		}
	}
	// i2c change
	else {
		// If SCL is high, non-data bit (START/STOP condition)
		// That is, data over SDA can only change while SCL is low
		if(PIN(SCL)) {
			if(PIN(SDA)) {
				// STOP
				state = IDLE;
			}
			else {
				// START
				nbits = 0;
				offset = 0;
				// always followed by a slave address
				state = WHO;
			}
		}
	}

	done: RETI();
}

// Respond to SCL change
ISR(INT0_vect) {
	// Cleared by stop condition
	if(state == IDLE) {
		goto done;
	}

	// Rising edge
	if(PIN(SCL)) {
		if(rw == WRITE) {
			// Read master's ACK
			if(ack) {
				FREE(SDA);
				if(PIN(SDA)) {
					// NAK, master wants to stop
					state = IDLE;
				}
			}

			goto done;
		}

		data <<= 1;
		data |= PIN(SDA);
		++nbits;

		if(nbits >= 8) {
			nbits = 0;

			if(state == WHO) {
				if(data>>1 == I2C_ADDR) {
					// Master read, slave write
					if(data&1) {
						rw = WRITE;
						state = START;
					}
					// Master write, slave read
					else {
						rw = READ;
						state = DATA;

					}
					ack = 1;
				}
				else {
					state = IDLE;
				}
			}
			else {
				set_bit(offset, PIN(SDA));
				++offset;
				if(offset >= sizeof(message)*8) {
					// Implicit NAK
					state = IDLE;
				}
				else if(offset%8 == 0) {
					// ACK
					ack = 1;
				}
			}
		}
	}
	// Falling edge
	else {
		if(ack) {
			if(rw == READ) {
				if(get_bit(offset)) {
					FREE(SDA);
				}
				else {
					HOLD(SDA);
				}
				++offset;
			}
		}
	}

	// Emitting reti directly prevents push/pops of registers to stack
	done: RETI();
}

[[noreturn]]
void main() {
	// Set up timer interrupt
	TCCR0B = 0b101; // Internal clock/1024
	TIMSK0 = 0b00;
	
	// Enable SCL as external interrupt
	EIMSK = 1; // Enable SCL as external interrupt
	EICRA = 0b01; // Logical change generates INT0

	// Set up pin change inerrupt
	DDRB = 0b0000;
	PCMSK = 0b0011; // Set SDA and CEC to use pin change
	PCICR = 1; // Enable pin change interrupt
	
	PUEB = 0b1111; // Set all 3 pins to pull-up

	state = IDLE;
	
	old_sda = PIN(SDA);
	old_cec = PIN(CEC);

	i2c_cmd = 0;
	offset = 0;
	length = 0;
	nbits = 0;

	cec_addr = 0x15;

	// Enable all interrupts
	sei();

	// Disable unused modules and sleep

	DIDR0 = 0b1000; // Disable pin 3 (unused)
	PRR = 0b10; // Disable ADC module
	SMCR = 0b1001; // Stand-by mode

	for(;;) asm("sleep");

	__builtin_unreachable();
}
