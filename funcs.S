#include "common.S"

/**
 * File holding subroutines which are common between the CEC and
 *  i2c protocol implementations.
 *
 * Doc format:
 *  func_name(depends): clobbers
**/

/**
 * push_bit(T): Z, data
 *
 * Push bit to the data register, Z=1 if a full byte is parsed
 *
 * Input: T flag, the value of the bit to push
 * Output: Z flag, use to determine if we hit the byte boundary
 * Clobber: ndata
**/
push_bit:
	lsl data // data <<= 1
	bld data, 0 // data[bit 0] = T
	dec nbits
	ret // Z flag preserved, can be used after return

/**
 * push_byte(Z, data): Z, it, length
 *
 * Push byte to the message buffer, does nothing if Z=0.
 *  Designed to be called immediately after push_bit, the
 *  two are separated because sometimes we want to build
 *  a byte without storing it to the message buffer.
 *
 * Input: Z, data
 * Output: Z flag, set if further writes will overflow
**/
push_byte:
	st it+, data
	inc length
	cpi length, 16
	ret

/**
 * next_bit(it): T
 *
 * Get the next bit from the message buffer, handling byte
 *  boundaries and setting Z=1 when further reads will
 *  overflow
**/
next_bit:
	bst data, 7
	lsl data // data <<= 1
	// if(--nbits == 0)
	dec nbits
	brne next_bit_done
		ldi nbits, 8
		ld data, it+
		// if(it >= message + length)
		ldi tmp, message
		add tmp, length
		cp it_lo, tmp
	next_bit_done:
	ret
