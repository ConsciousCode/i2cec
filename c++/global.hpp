#ifndef GLOBAL_HPP
#define GLOBAL_HPP

#include "arch.hpp"
#include "config.h"

/*
 * Interoperation buffer between i2c and CEC. Has 1 byte for
 *  an i2c command and 16 bytes for CEC messages to write.
*/
union Message {
	byte buffer[1 + BUFFER_SIZE];
	struct {
		byte reg;
		union {
			byte payload[BUFFER_SIZE];
			uint16_t taken;
			byte value;
		};
	};
};

// Global BitField
union GBF {
	byte value;
	struct {
		// Record CEC messages regardless of target
		bool monitor : 1;
		// Interrupts return immediately, used to wake from sleep or
		//  detect i2c START/STOP conditions
		bool nest : 1;
		// Whether the current CEC message is addressed to us
		bool mine : 1;
		// CEC EOM bit
		bool eom : 1;
		// For either i2c or CEC, whether or not the address byte has
		//  been processed yet.
		// Note: Might be mutually exclusive with EOM
		bool who : 1;
		
		// Whether or not the buffer contains data from CEC
		bool cec : 1;
	};
};

extern Message msg;
extern uint16_t taken_vec; // taken addresses

register GBF flags asm("18");
static Register<19> length;
static Register<20> cec_addr;

extern const char id_str[8];

#endif
