#ifndef I2CEC_COMMON
#define I2CEC_COMMON

#include "config.h"

#define message (RAMSTART + 0) // Address of message buffer

// Register assignment (arbitrary)
#define gbf 16 // general bit field
#define state 17 // state for FSM
#define data 18 // framed data buffer
#define nbits 19 // # of bits in data
#define tmp 20 // General-use temporary
#define length 21 // Length of the message buffer
#define cec_addr 22 // CEC address
#define cmd 23 // Command being processed
#define r24
#define r25

// Use X register for offset into the message buffer
#define it X
#define it_lo 26
#define it_hi 27
// We won't use high(X) ever, but it can't be set either.
//  It should always be 0, so best take advantage of it!
#define __zero_reg__ it_hi

// Use Y register for the taken vector
#define taken_lo 28 // Y low
#define taken_hi 29 // Y high

// Used for iterating over program memory constants
#define Z_lo 30 // Z low
#define Z_hi 31 // Z high

/// Constants

// State values
//  IDLE is the only one which can't be changed
#define IDLE 0 // Ignoring the bus / don't want arbitration

#define START 1 // Reading the START condition of CEC
#define EOM 2 // Reading the CEC EOM bit
#define WHO 3 // Reading the address component
#define CMD 4 // Reading the i2c command
#define WAIT 5 // Waiting for opportunity to arbitrate on CEC
#define DATA 6 // Reading data
#define DEVID 7 // i2c device id subprotocol
#define EXEC 8 // Waiting for parameter of action command

/// GBF (Global bit field)
// Bit locations which are algorithmically required
#define OLD_CEC CEC
#define OLD_SDA SDA
// ACK needs to be +1 of RW
#define RW 2 // 0 = write, 1 = read
#define ACK (RW+1) // ACK reverses rw for one bit

// Bit locations which can be anything
#define HILO 4 // hi/lo state of CEC
#define I2CEC 5 // Which bus we're interacting with
#define MONITOR 6 // Whether or not we're in "monitor mode"
#define DEBUG 7 // Debug mode

/// Renaming weird-sounding SFRs
#define COUNTER TCNT0L
#define TIMEOUT OCR0AL
#define TIMER TCCR0B

/// Timing calculation

// Note: Changing these only changes the calculation of
//  "jiffies" for timing, it won't affect the actual
//  timer control flags.
#define CLOCK_HZ 8000000
#define CLOCK_DIV 1024

// See config.h for CLOCK_HZ and CLOCK_DIV
#define TIMER_HZ (CLOCK_HZ/CLOCK_DIV)

// Times are in microseconds 
#define JIFFY (1000000/TIMER_HZ) // Jiffy = us/tick
#define TIME_1 600 // Low time of CEC 1 bit
#define TIME_0 1500 // Low time of CEC 0 bit
#define TIME_BIT 4500 // Total time of CEC bit
#define TIME_E 150 // Allowed error in CEC timing
#define TIME_START0 3700 // CEC START low component
#define TIME_START1 600 // CEC START high component

// Measured in jiffies
#define JIFFY_BIT (TIME_BIT/JIFFY)

#define JIFFY_1_LO (TIME_1/JIFFY)
#define JIFFY_1_HI (JIFFY_BIT - JIFFY_1_LO)

#define JIFFY_0_LO (TIME_0/JIFFY)
#define JIFFY_0_HI (JIFFY_BIT - JIFFY_0_LO)

#define JIFFY_DATA_MID ((JIFFY_1_LO + JIFFY_0_HI)/2)

#define JIFFY_E (TIME_E/JIFFY)

#define JIFFY_START_LO (TIME_START0/JIFFY)
#define JIFFY_START_HI (TIME_START1/JIFFY)
#define JIFFY_START_MID ((JIFFY_START_LO + JIFFY_START_HI)/2)
#define JIFFY_START (JIFFY_START_LO + JIFFY_START_HI)

/// Macros

.altmacro

.set _done_incr, 0

.macro __mklabel nonce
	__done_\nonce\():
	.set done, __done_\nonce
.endm
.macro done
	__mklabel %_done_incr
		reti
	.set _done_incr, _done_incr+1
.endm

// Given pin becomes output, holding bus low
.macro HOLD pin
	sbi DDRB, \pin
.endm

// Given pin becomes input, freeing bus
.macro FREE pin
	cbi DDRB, \pin
.endm

.macro enable_timer
	ldi tmp, 0b101
	out TIMER, tmp
.endm

.macro disable_timer
	out TIMER, __zero_reg__
.endm

.macro clear_timer
	out TIMEOUT, __zero_reg__
.endm

.macro set_timeout tout
	ldi tmp, tout
	out TIMEOUT, tmp
.endm

.macro set_flag flag
	sbr gbf, 1<<\flag
.endm
.macro clear_flag flag
	cbr gbf, 1<<\flag
.endm

.macro if_clear flag, dst
	sbrs gbf, \flag
	rjmp dst
.endm
.macro if_set flag, dst
	sbrc gbf, \flag
	rjmp dst
.endm

.macro if_low pin, dst
	sbis gbf, \pin
	rjmp dst
.endm
.macro if_high pin, dst
	sbic gbf, \pin
	rjmp dst
.endm

.macro if_state sv, dst
	cpi state, sv
	breq dst
.endm

.macro if_data sv, dst
	cpi data, sv
	breq dst
.endm

.macro if_cmd sv, dst
	cpi cmd, sv
	breq dst
.endm

// No addi, but there IS a subi
.macro addi a, b
	subi \a, -\b
.endm

#endif
