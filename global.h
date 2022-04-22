#ifndef GLOBAL_H
#define GLOBAL_H

#include "config.h"
#include "timing.h"

// So the IDE doesn't get confused
#ifndef __AVR_ATtiny10__
	#define __AVR_ATtiny10__
#endif
//#undef _SFR_ASM_COMPAT
#define __SFR_OFFSET 0 // Hack to make IO addresses use in/out
#include <avr/io.h>

#ifndef __ASSEMBLER__
	#include <avr/interrupt.h>
	#include <avr/sfr_defs.h>
	#include <avr/wdt.h>
	#include <avr/sleep.h>
	#include <avr/power.h>
	#include <avr/pgmspace.h>
	#include <util/delay_basic.h>

	#include <stdbool.h>
#endif

#define __naked __attribute__((naked))

// T flag instruction macros
#define set() asm volatile("set\n")
#define clt() asm volatile("clt\n")
#define bld(r, b) asm("bld %0, %1\n" : "+r"(r) : "I"(b))
#define bst(r, b) asm volatile("bst %0, %1\n" :: "r"(r), "I"(b))
#define brtc(lbl) asm goto("brtc %l0\n" :::: lbl)
#define brts(lbl) asm goto("brts %l0\n" :::: lbl)

#define lsl(r) asm("lsl %0\n" : "+r"(r))
#define lsr(r) asm("lsr %0\n" : "+r"(r))

#define lo4(x) ((x)&0xf)
#define hi4(x) (((x)>>4)&0xf)
#define lo8(x) ((x)&0xff)
#define hi8(x) (((x)>>8)&0xff)
#define get_bit(x, r) ((x) & _BV(r))
#define set_bit(x, r) ((x) |= _BV(r))
#define clr_bit(x, r) ((x) &= ~_BV(r))

#define get_flag(f) get_bit(flags, f)
#define set_flag(f) set_bit(flags, f)
#define clr_flag(f) clr_bit(flags, f)

#define rcall(lbl) asm goto("rcall %l0\n" :::: lbl)
#define ret() asm volatile("ret\n" ::);

// All pins set as low out, changing to IN stops holding
#define HOLD(p) set_bit(DDRB, p)
#define FREE(p) clr_bit(DDRB, p)

#define PIN(p) bit_is_set(PINB, p)

#define await_low(p) loop_until_bit_is_clear(PINB, (p))
#define await_high(p) loop_until_bit_is_set(PINB, (p))

// EIFR needs to be cleared (write logic 1) before EICR otherwise
//  pending interrupts will be processed immediately if in sei
#define enable_int0() do { set_bit(EIFR, 0); set_bit(EIMSK, 0); } while(0)
#define disable_int0() clr_bit(EIMSK, 0)
#define set_int0_mode(im) (EICRA = (im))

#define enable_pcint0() do { set_bit(PCIFR, 0); set_bit(PCICR, 0); } while(0)
#define disable_pcint0() clr_bit(PCICR, 0)

#define enable_error_timeout() set_bit(TIMSK0, OCIE0B)
#define disable_error_timeout() clr_bit(TIMSK0, OCIE0B)

#define enable_timeout() set_bit(TIMSK0, OCIE0A)
#define disable_timeout() clr_bit(TIMSK0, OCIE0A)

// Timeout used when CEC takes too long, which aborts CEC reads
#define set_error_timeout(ticks) (OCR0B = (ticks))
#define set_timeout(ticks) (OCR0A = (ticks))

#define restart_timer() (TCNT0 = 0)

#define enable_cec() enable_int0()
#define disable_cec() disable_int0()

#define enable_i2c() enable_pcint0()
#define disable_i2c() disable_pcint0()

/*
 * Here lies black magic.
 * Verified via assembly that the optimized code links brtc to the
 *  else clause.
 */
#define _CAT_IMPL(x, y) x ## y
#define _CAT(x, y) _CAT_IMPL(x, y)
#define _IF_T_IMPL2(t0, t1) brtc(t0); goto t1; t0: if(0) t1:
#define _IF_T_IMPL1(cnt) _IF_T_IMPL2(_CAT(T0_, cnt), _CAT(T1_, cnt))
#define if_T() _IF_T_IMPL1(__COUNTER__)

// Toggles PORT
#define PING(pin) set_bit(PINB, pin)

// SPL = this will unwind the stack to one return address
#define STACK_UNWIND (RAMEND - 2)

#define unreachable() __builtin_unreachable()

#ifndef __ASSEMBLER__

register uint8_t length asm("18");
register uint8_t data asm("19");
register uint8_t cec_addr asm("20");
register uint8_t reg asm("21");

// Interrupts return immediately, used to wake from sleep or
//  detect i2c START/STOP conditions
#define FLAG_NEST 0
// Both used for temporary bit storage (other than T)
#define FLAG_RW 1
#define FLAG_EOM 2
// Set when i2c wrote to buffer so main can call cec_write
#define FLAG_CEC 3

register uint8_t flags asm("22");

register uint16_t taken asm("26"); // X
// Y = 28:29
// Z = 30:31

uint8_t buffer[BUFFER_SIZE];

const char IDENT_STR[IDENT_SIZE] PROGMEM = IDENT;

enum InterruptMode {
	LOW = 0,
	CHANGE = 1,
	FALL = 2,
	RISE = 3
};

#endif
#endif
