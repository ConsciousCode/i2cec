#include "global.h"

// Go to sleep waiting for an interrupt
void resume_timeout() {
	sei();
	sleep_cpu();
}

// Restart the timer and go to sleep
void await_timeout() {
	restart_timer();
	resume_timeout();
}

// Both cec_read and cec_write use the same logic at the end
void cec_rw_common() {
	await_timeout();
	
	// Read: Free to prevent overwriting
	// Write: Release the bus
	FREE(CEC);
	// Read: The high/low state corresponds to the read bit
	// Write: Read the state of the bus to detect lost arbitration
	bst(PINB, CEC); // Either 
	// Timeout for the rest of the bit timing
	set_timeout(TICKS_BIT);
	
	resume_timeout();
}

void cec_read_bit() {
	set_timeout(TICKS_SAMP);
	cec_rw_common();
}

void cec_write_bit() {
	register uint8_t tmp;// asm("16");
	
	if_T() tmp = TICKS_1_LO;
	else tmp = TICKS_0_LO;
	set_timeout(tmp);
	
	HOLD(CEC);
	cec_rw_common();
}

// Write the buffer to CEC
void cec_write() {
	goto start;
	for(;;) {
	// Another device is using the bus, retry after a delay
	lost_arbitration:
		set_timeout(TICKS_BIT*3);
		await_timeout();
	start:
		HOLD(CEC);
		set_timeout(TICKS_START_LO);
		await_timeout();
		
		FREE(CEC);
		
		if(PIN(CEC)) goto lost_arbitration;
		
		set_timeout(TICKS_START);
		resume_timeout();
		
		register uint8_t* it = &buffer[0];
		register uint8_t len asm("23") = length;
		
		do {
			//*it++ = data;
			asm("ld %0, %a1+\n" : "=r"(data), "+e"(it));
			
			// cec_write_byte()
			// Can't be a separate function because it has two exits
			register uint8_t nbits asm("24") = 8;
			set_bit(PORTB, SCL);
			do {
				bst(data, 7);
				lsl(data);
				cec_write_bit();
				brtc(lost_arbitration);
			} while(--nbits);
			clr_bit(PORTB, SCL);
			
			// assert: T = 1
			
			// EOM bit
			if(--len == 0) clt();
			cec_write_bit();
			brtc(lost_arbitration);
			
			// ACK bit
			cec_read_bit();
			brts(done);
		} while(len);
	}
done:
	return;
}

void cec_read_byte() {
	register uint8_t nbits asm("22") = 8;
	data = 0;
	
	do {
		// Synchronize to falling edge
		await_timeout();
		// Disable edge detection
		disable_cec();
			cec_read_bit();
			lsl(data);
			bld(data, 0);
		enable_cec();
	} while(--nbits);
	
	// Synchronize to falling edge
	await_timeout();
}

/**
 * Unlike i2c, CEC is such a low-baud protocol that most of the time
 *  spent read/writing is actually spent waiting for a timer to go
 *  off so no special considerations are needed for speed.
 * 
 * Note that sei is handled by functions, you can assume any code
 *  within the interrupt is cli.
**/
ISR(INT0_vect, ISR_NAKED) {
	// If nested, normal return to keep implicit cli - whatever had
	//  the interrupt enabled was waiting for a falling edge
	if(get_flag(FLAG_NEST)) {
		PING(SDA);
		ret();
	}
	set_flag(FLAG_NEST);
	
	// Disable i2c while we process CEC
	disable_i2c();
	
	/**
	 * START condition is special in that it uses a different timing
	 *  than normal bits. That means to detect it properly (and
	 *  ensure it isn't just in the middle of a desynchronized
	 *  message) we have to detect a bus RISE explicitly.
	**/
	set_int0_mode(RISE);
	enable_error_timeout();
	set_error_timeout(TICKS_START);
	await_timeout();
	
	// Rest of the bits are sync'd by falling edge
	set_int0_mode(FALL);
	
	if(TCNT0 >= TICKS_START_LO - TICKS_E) {
		set_error_timeout(TICKS_BIT*3/2);
		
		cec_read_byte();
		taken |= _BV(hi4(data));
		
		if(cec_addr == CEC_DEFAULT || lo4(data) == cec_addr) {
			register uint8_t* it = &buffer[0];
			data = cec_addr;
			length = 1;
			
			asm("st %a0+, %1\n" : "+e"(it) : "r"(data));
			
			do {
				cec_read_byte();
				asm("st %a0+, %1\n" : "+e"(it) : "r"(data));
				
				// Disable edge detection
				disable_cec();
					// flags.tmp = EOM
					cec_read_bit();
					bld(flags, FLAG_EOM);
					cec_read_bit(); // NAK
				enable_cec();
				
				brtc(cleanup);
					
				if(get_flag(FLAG_EOM)) goto cleanup;
			} while(++length < 16);
		
		cleanup: ;
		#ifdef DIRTY
			// Set when the new message is finished reading
			set_bit(PORTB, DIRTY);
		#endif
		}
	}
	
	disable_error_timeout();
	enable_i2c();
	clr_flag(FLAG_NEST);
	
	reti();
}
