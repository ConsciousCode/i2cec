#ifndef ARCH_HPP
#define ARCH_HPP

#include <stdint.h>
#include <avr/io.h>
#include <avr/sfr_defs.h>

#include "util.hpp"

// Inline assembly macros

#define sbr(x, f) asm("sbr %0, 1<<%1" :"+r"(x) :"I"(f))
#define cbr(x, f) asm("cbr %0, 1<<%1" :"+r"(x) :"I"(f))

#define bld(x, b) asm("bld %0, %1" : "+r"(x) : "p"(b))
#define bst(x, b) asm volatile("bst %0, %1" : "+r"(x) : "p"(b) : "cc")
#define set() asm volatile("set" ::: "cc")
#define clt() asm volatile("clt" ::: "cc")

// GCC doesn't like to generate these with global register variables
#define inc(x) asm("inc %0" :"+r"(x) :: "cc")
#define dec(x) asm("dec %0" :"+r"(x) :: "cc")

#define REQUIRE(x) asm volatile("" :: "r"(x))

// Have to be used explicitly because usually the generated code is:
// in tmp, io
// ori tmp, _BV(bit)
// out io, tmp
#define sbi(x, f) do {\
	static_assert((int)&(x) < __SFR_OFFSET + 0x20, "sbi can only accept io addresses < 0x20"); \
	asm volatile("sbi %0, %1" ::"I"(&(x)),"I"(f)); } while(0)
#define cbi(x, f) do {\
	static_assert((int)&(x) < __SFR_OFFSET + 0x20, "sbi can only accept io addresses < 0x20"); \
	asm volatile("cbi %0, %1" ::"I"(&(x)),"I"(f)); } while(0)

/**
 * Some C++ magic to make low-level programming C++-like
**/

typedef uint8_t byte;

struct SReg_T;

template<int REG>
struct Register {
	static_assert(REG > 15 && REG < 32, "Register must be r16-32");
	
	struct Subtype {
		inline operator Register<REG>() const {
			return {};
		}
	};
	
	struct Bit {
	protected:
		const byte& bit;
	public:
		inline Bit(const byte& b):bit(b) {}
		
		inline Bit& operator=(SReg_T);
		
		inline Bit& operator=(bool b) {
			if(b) asm("sbr %0, %1" :: "I"(REG), "I"(bit));
			else asm("cbr %0, %1" :: "I"(REG), "I"(bit));
			
			return *this;
		}
		
		inline operator bool() const {
			asm goto(
				"sbrs %0, %1\n"
				"rjmp %l2"
				:: "I"(REG), "I"(bit)
				:: reg_clr
			);
			reg_set: return true;
			reg_clr: return false;
		}
	};
	
	struct ZFlag : Subtype {
		inline operator bool() const {
			asm goto("brne %l0" :::: B_NZ);
			B_Z: return false;
			B_NZ: return true;
		}
	};
	
	inline operator bool() const {
		asm goto(
			"and %0, %0\n"
			"brne %l1"
			:: "I"(REG)
			:: B_NZ
		);
		B_Z: return false;
		B_NZ: return true;
	}
	
	inline Register() {}
	
	template<typename T>
	inline Register(T x) {
		*this = (byte)x;
	}
	
	inline ZFlag operator=(const byte& x) {
		asm("ldi %0, %1" :: "I"(REG), "X"(x));
	}
	
	template<int R>
	inline ZFlag operator=(Register<R>) {
		asm("mov %0, %1" :: "I"(REG), "I"(R));
	}
	
	inline ZFlag operator++() {
		asm("inc %0" :: "I"(REG));
		return {};
	}
	inline ZFlag operator--() {
		asm("dec %0" :: "I"(REG));
		return {};
	}
	
	__attribute__((optimize("unroll-loops")))
	inline ZFlag operator<<=(const byte& x) {
		for(int i = 0; i < x; ++i) {
			asm("lsl %0" :: "I"(REG));
		}
		return {};
	}
	__attribute__((optimize("unroll-loops")))
	inline ZFlag operator>>=(const byte& x) {
		for(int i = 0; i < x; ++i) {
			asm("lsr %0" :: "I"(REG));
		}
		return {};
	}
	
	inline ZFlag operator+=(const byte& x) {
		return *this -= -x;
	}
	
	inline ZFlag operator-=(const byte& x) {
		asm("subi %0, %1" :: "I"(REG), "I"(x));
		return {};
	}
	
	inline Bit operator[](const byte& x) {
		return Bit(x);
	}
	
	inline const Bit operator[](const byte& x) const {
		return Bit(x);
	}
};
struct empty {
	int : 0;
};
constexpr int x = sizeof(empty);

static struct SReg_T {
	struct not_T {
		inline operator bool() const {
	
			asm goto("brtc %l0" :::: T_1);
			T_0: return false;
			T_1: return true;
		}
	};
	
	inline not_T operator!() const { return {}; }
	
	inline operator bool() const {
		asm goto("brts %l0" :::: T_1);
		T_0: return false;		
		T_1: return true;
	}
	
	inline SReg_T& operator=(bool x) {
		if(x) set();
		else clt();
		
		return *this;
	}
	
	template<int REG>
	inline SReg_T& operator=(const typename Register<REG>::Bit& b) {
		// b.reg is rw instead of r because otherwise the compiler
		//  optimizes it out as dead code for some reason
		asm("bst %0, %1" :: "I"(REG), "I"(b.bit));
		return *this;
	}
} T;

template<int REG>
typename Register<REG>::Bit& Register<REG>::Bit::operator=(SReg_T) {
	asm("bld %0, %1" :: "I"(REG), "I"(bit));
	return *this;
}

#define LOWER_X x
#define LOWER_Y y
#define LOWER_Z z

#define LOWER(x) CAT(LOWER_, x)

#define ld_inc(reg) ({ byte t, *it; \
	asm("ld %0, " #reg "+" : "=&r"(t), STR(+LOWER(reg)) (it)); t; })

#define st_inc(reg) ({ byte* it; \
	asm("st " #reg "+, %0" :: "r"(v), STR(LOWER(reg)) (it)); })

template<char REG>
struct Regimpl {
	static byte inc_deref();
	static void inc_assign(byte v);
	static void assign(byte* v);
};

template<char REG>
struct PointerRegister {
	struct inc {
		struct deref {
			inline operator byte() const {
				return Regimpl<REG>::inc_deref();
			}
			inline deref& operator=(byte v) {
				Regimpl<REG>::inc_assign(v);
				return *this;
			}
		};
		
		inline deref operator*() { return {}; }
	};
	
	inline inc operator++(int) { return {}; }
	
	inline auto operator=(byte* v) -> decltype(*this) {
		Regimpl<REG>::assign(v);
		return *this;
	}
};

template<>
struct Regimpl<'X'> {
	static byte inc_deref() {
		return ld_inc(X);
	}
	
	static void inc_assign(byte v) {
		st_inc(X);
	}
	
	static void assign(byte* v) {
		byte* it = v;
		asm volatile("" : "+x"(it));
	}
};

template<>
struct Regimpl<'Y'> {
	static byte inc_deref() {
		return ld_inc(Y);
	}
	
	static void inc_assign(byte v) {
		st_inc(Y);
	}
	
	static void assign(byte* v) {
		byte* it = v;
		asm volatile("" : "+y"(it));
	}
};

template<>
struct Regimpl<'Z'> {
	static byte inc_deref() {
		return ld_inc(Z);
	}
	
	static void inc_assign(byte v) {
		st_inc(Z);
	}
	
	static void assign(byte* v) {
		byte* it = v;
		asm volatile("" : "+z"(it));
	}
};

static PointerRegister<'X'> X;
static PointerRegister<'Y'> Y;
static PointerRegister<'Z'> Z;

#endif
