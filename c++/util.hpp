#ifndef UTIL_HPP
#define UTIL_HPP

#define EMPTY(...)
#define DEFER(m) m EMPTY()
#define EVAL(...) EVAL4(__VA_ARGS__)

#define EVAL4(...) EVAL2(EVAL2(__VA_ARGS__))
#define EVAL2(...) EVAL1(EVAL1(__VA_ARGS__))
#define EVAL1(...) __VA_ARGS__

#define _STR(x) #x
#define STR(x) _STR(x)

#define _CAT(x, y) x ## y
#define CAT(x, y) _CAT(x, y)

#define LABEL(name) CAT(name, __COUNTER__)

#define dec_loop_impl(x, lbl) \
	if(1) goto lbl; \
	else while(1) \
		if(1) { \
			asm volatile("dec %0" : "+r"(x)); \
			asm goto("brne %l0" :::: lbl); \
			break; } \
		else lbl:
#define dec_loop(x) dec_loop_impl(x, LABEL(next))

#define repeat(x) if(byte it = (x) || 1) dec_loop(it)

#define __inline inline __attribute__((always_inline))

#define await_low(p) loop_until_bit_is_clear(PINB, p)
#define await_high(p) loop_until_bit_is_set(PINB, p)

#define lo4(x) ((x)&0x0f)
#define hi4(x) (((x)>>4)&0x0f)

#define lo8(x) ((x)&0xff)
#define hi8(x) (((x)>>8)&0xff)

#define SET(x, p) x |= _BV(p)
#define CLR(x, p) x &= ~_BV(p)

#define OUT(p) sbi(DDRB, p)
#define IN(p) cbi(DDRB, p)

#define PIN(p) bit_is_set(PINB, p)
// All pins set as low out, changing to IN stops holding
#define HOLD(p) OUT(p)
#define FREE(p) IN(p)

enum InterruptMode {
	LOW = 0,
	CHANGE = 1,
	FALL = 2,
	RISE = 3
};

#define enable_int0() sbi(EIMSK, 0)
#define disable_int0() cbi(EIMSK, 0)
#define set_int0_mode(im) EICRA = im

#define enable_pcint0() do { sbi(PCIFR, 0); sbi(PCICR, 0); } while(0);
#define disable_pcint0() cbi(PCICR, 0)

#define enable_tim0_compa() SET(TIMSK0, OCIE0A)
#define disable_tim0_compa() CLR(TIMSK0, OCIE0A)

#define enable_tim0_compb() SET(TIMSK0, OCIE0B)
#define disable_tim0_compb() CLR(TIMSK0, OCIE0B)

#define set_timeout_a(ticks) OCR0A = ticks
#define set_timeout_b(ticks) OCR0B = ticks

#define restart_timer() TCNT0 = 0

#define enable_cec() enable_int0()
#define disable_cec() disable_int0()

#define enable_i2c() enable_pcint0()
#define disable_i2c() disable_pcint0()

#endif
