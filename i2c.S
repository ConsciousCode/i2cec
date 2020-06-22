#include "config.h"

// Read the next i2c bit
i2c_read_bit:
	await_low SCL
	disable_i2c
	
	FREE SDA
	
	await_high SCL
	enable_i2c
	
	in tmp, PINB
	bst tmp, SDA
	ret

// Write an i2c bit
i2c_write_bit:
	await_low SCL
	
	brtc T_0
	T_1:
		FREE SDA
	T_0:
		HOLD SDA
	
	await_high SCL
	await_low SCL
	
	ret

i2c_read_byte:
	ldi data, 0
	
	ldi nbits, 8
	i2c_read_loop:
		rcall i2c_read_bit
		lsl data
		bld data, 0
	dec_loop nbits, i2c_read_loop
	
	ret

i2c_write_byte:
	ldi nbits, 8
	i2c_write_loop:
		bst data, 7
		lsl data
		rcall i2c_write_bit
	dec_loop nbits, i2c_write_loop
	
	ret

i2c_write_ack:
	disable_i2c
		clt
		rcall i2c_write_bit
	enable_i2c
	ret

memcpy:
	ld tmp, Y+
	st Z+, tmp
	
	dec_loop len, memcpy
	
	ret

__pcint0_vect:
__vector_2:
	// This is handled in the IVT
	//if(!PIN(SCL)) reti()
	
	if_clear NEST, i2c_read
		
		// Unwind stack
		out SPL, stack_unwind
		
		// Load register
		lds reg, i2c_reg
		
		dump_byte reg
		
		case reg, REG_CEC, case_REG_CEC
		case reg, REG_ID, case_REG_ID
		case reg, REG_ADDR, case_REG_ADDR
		
		rjmp i2c_read
		
		// Unreachable
		id_str: .string IDENT
		id_len = .-id_str
		.balign 2
		
		case_REG_CEC:
			sbrs flags, DIRTY
				ldi length, 0
			
			disable_i2c
				enable_tim0_compb
				rcall cec_write
			enable_i2c
			
			rjmp i2c_read
		
		case_REG_ID:
			ldi len, id_len
			set_Y pm(id_str)
			set_Z buffer
			
			rcall memcpy
			
			rjmp i2c_read
		
		case_REG_ADDR:
			cpi length, 1
			brne i2c_reg_addr_w
			i2c_reg_addr_r:
				sts buffer, cec_addr
				rjmp i2c_read
			
			i2c_reg_addr_w:
				lds cec_addr, buffer
				rjmp i2c_read
	
	i2c_read:
	
	set_flag NEST
	disable_cec
	// Disable pcint so it's not executed on sei()
	disable_i2c
	sei
	
	sbic PINB, SDA
		rjmp i2c_stop
	
	i2c_start:
		set_Z buffer
		clear_flag WHO
		
		i2c_read_data:
			rcall i2c_read_byte
			
			if_clear WHO, i2c_not_who
			
			i2c_who:
				bst data, 0
				lsr data
				
				cpi data, I2C_ADDR
				brne i2c_nack
				
				brtc i2c_t_0
				i2c_t_1:
					tst length
					breq i2c_nack
						rcall i2c_write_ack
						
						// 1 = read, write buffer contents
						
						i2c_write_data:
							ld data, Z+
							rcall i2c_write_byte
							rcall i2c_read_bit
							brts i2c_nack	
						dec_loop length, i2c_write_data
						
						rjmp i2c_nack
				i2c_t_0:
					set_flag WHO
					ldi length, 0
					rjmp i2c_ack
			
			i2c_not_who:
				st Z+, data
				inc length
				cpi length, 1 + BUFFER_SIZE
				brcc i2c_nack
			
			i2c_ack:
				rcall i2c_write_ack
			
			rjmp i2c_read_data
		
		i2c_nack:
			FREE SDA
	
	i2c_stop:
		// do nothing
	
	enable_i2c
	enable_cec
	clear_flag NEST
	
	reti
