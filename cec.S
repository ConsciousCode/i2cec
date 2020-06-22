#include "config.h"
#include "timing.h"

await_next_int:
	restart_timer
	// fallthrough
resume_next_int:
	sei
	sleep
	ret

cec_rw_common:
	rcall await_next_int
	
	FREE CEC
	bst PINB, CEC
	set_timeout_b TICKS_BIT
	
	// rjmp = tail call optimization
	rjmp resume_next_int

cec_read_bit:
	set_timeout_b TICKS_SAMP
	rjmp cec_rw_common

cec_write_bit:
	brts cec_write_1
	cec_write_0:
		set_timeout_b TICKS_0_LO
		rjmp cec_write_after
	cec_write_1:
		set_timeout_b TICKS_1_LO
	cec_write_after:
	
	HOLD CEC
	rjmp cec_rw_common

// Another device is using the bus, retry after a delay
cec_lost_arbitration:
	set_timeout_b TICKS_BIT*3
	rcall await_next_int
	// fallthrough

cec_write:
	HOLD CEC
	set_timeout_b TICKS_START_LO
	rcall await_next_int
	// cli
	FREE CEC
	
	sbic PINB, CEC
		rjmp cec_lost_arbitration
	
	set_timeout_b TICKS_START
	rcall resume_next_int
	// cli
	
	set_Z buffer
	mov len, length
	
	cec_write_data:
		ld data, Z+
		
		ldi nbits, 8
		cec_write_byte:
			bst data, 7
			lsl data
			rcall cec_write_bit
			
			brtc cec_lost_arbitration
			
			dec_loop nbits, cec_write_byte
		
		// assert: T = 1
		dec len
		
		brne cec_eom_1
		cec_eom_0:
			clt
		cec_eom_1:
		
		rcall cec_write_bit
		brtc cec_lost_arbitration
		
		rcall cec_read_bit
		brts cec_done
		
		tst len
		brne cec_write_data
	
	cec_done:
		disable_tim0_compb
	ret

__int0_vect:
__vector_1:
	reti
	// Reused interrupt to wake from sleep. Use a normal return to
	//  keep the interrupt enable off
	sbrc flags, NEST
		ret
	
	// Reuse the interrupt for rising edge detection
	set_flag NEST
	
	// Disable i2c while we process CEC
	disable_i2c
	
	// Detect rising edge for START condition
	set_int0_mode RISE
	
	// Set a timeout to break out of CEC if it takes too long
	set_timeout_a TICKS_START
	enable_tim0_compa
	
	rcall await_next_int
	//cli
	
	// Right now, only int0 and tim0_compa are enabled. tim0_compa
	//  will cancel CEC processing, int0 will resume here.
	
	// Rest of the bits are processed by timing and sync'd by
	//  falling edge
	set_int0_mode FALL
	
	// if(TCNT0 >= TICKSHOLD_START_LO - TICKS_E)
	in tmp, TCNT0H
	cpi tmp, hi8(TICKS_START_LO - TICKS_E)
	brlt cec_cleanup2 // >= impossible
	brcs cec_start // Carry set, lhs > rhs, >= satisfied
	
	// hi8 ==, >= depends on lo8
	in tmp, TCNT0L
	cpi tmp, lo8(TICKS_START_LO - TICKS_E)
	brlt cec_cleanup2
	
	cec_start:
		set_Z buffer
		
		// Cancel CEC if a bit takes too long
		set_timeout_a TICKS_BIT*3/2
		
		clear_flag WHO
		
		cec_read_data:
			ldi data, 0
			
			ldi nbits, 8
			cec_read_byte:
				rcall await_next_int
				disable_int0
					rcall cec_read_bit
					lsl data
					bld data, 0
				enable_int0
				
				dec_loop nbits, cec_read_byte
			
			rcall await_next_int
			disable_int0
			rcall cec_read_bit // T = EOM
			
			if_set WHO, cec_data
			
			cec_who:
				//if(data == CEC_DEFAULT)
				cpi data, CEC_DEFAULT
				breq cec_who_done
				
				// else if(data == cec_addr)
				cp data, cec_addr
				brne cec_not_me
					set_flag MINE
					rjmp cec_who_done
				cec_not_me:
				
				set_flag WHO
				
			cec_data:
			
			// T = flags.EOM
			bld flags, EOM
			
			st Z+, data
			
			if_clear MINE, cec_flag_not_mine
			
			cec_flag_mine:
				set
				rcall cec_write_bit
				rjmp cec_got_ack
			
			cec_flag_not_mine:
				rcall cec_read_bit
				brts cec_got_ack
				rjmp cec_cleanup
			
			cec_got_ack:
			
			if_set EOM, cec_cleanup
			
			enable_int0
			
			inc length
			cpi length, 16
			brcc cec_read_data
			
			// We finished reading CEC bus, it's ready to be read
			set_flag DIRTY

	cec_cleanup:
	
	cbr flags, (1<<WHO)|(1<<MINE)|(1<<EOM)|(1<<EOM)
	
	disable_tim0_compa
	enable_i2c
	
	reti
