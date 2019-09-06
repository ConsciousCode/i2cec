#ifndef I2CEC_COMMON_H
#define I2CEC_COMMON_H

#include <avr/io.h>
#include "config.h"

#define message 0 // Address of message buffer

; Register assignment
#define gbf 16  // general bit field
#define state 17  // state for FSM
#define data 18  // framed data buffer
#define nbits 19  // # of bits in data, ~4 bits
#define tmp 20  // General-use temporary
#define length 21  // Length of the message buffer
#define cec_addr 22  // CEC address, 4 bits
#define cmd 23 // Command for what to do with the message buffer
#define srcdst 24
#define r25

; Use X register for offset into the message buffer
#define it X
#define it_lo 26
#define it_hi 27
; We won't use high(X) ever, but it can't be set either.
#define __zero_reg__ 27

; Use Y register for the taken vector
#define taken_lo 28 // Y low
#define taken_hi 29 // Y high

#define r30 // Z low
#define r31 // Z high

;; Constants

; State values
#define IDLE 0  // Ignoring the bus / don't want arbitration
#define START 1
#define EOM 1
#define WHO 2  // Reading the address component
#define STOP 3  // Reading the stop condition
#define WAIT 4  // Waiting for opportunity to arbitrate on CEC
#define DATA 5  // Reading data
#define POLL 6  // Reading ACK of CEC poll message

;; GBF bit fields
; Bit locations which are algorithmically required
#define OLD_CEC CEC
#define OLD_SDA SDA

; Bit locations which can be anything
#define RW 2  // 0 = write, 1 = read
#define ACK 3  // ACK reverses rw for one bit
#define LOHI 4  // lo/hi state of CEC

;; Misc
#define COUNTER TCNT0L
#define TIMEOUT OCR0AL
#define TIMER TCCR0B

;; Macros

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

; Given pin becomes output, holding bus low
.macro HOLD pin
	sbi DDRB, \pin
.endm

; Given pin becomes input, freeing bus
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

#endif
