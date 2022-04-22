#include "global.h"
#include "cec.c"
#include "i2c.c"

__attribute__((noreturn)) __naked void main() {
	// Disable unused modules
	set_bit(ACSR, ACD); // Analog Comparator Disable
	set_bit(PRR, PRADC); // Power Reduction ADC (but not timer)
	set_bit(DIDR0, RESET); // Digital Input Disable
	
	// Allow buses to float high in input mode
	PUEB = _BV(SDA)|_BV(SCL)|_BV(CEC); // Pull-Up Enable
	
#ifdef DIRTY
	set_bit(DDRB, DIRTY);
#endif
	
	set_bit(SMCR, SE); // Sleep Enable
	
	// Set up interrupts
	
	// External interrupt (INT0)
	set_int0_mode(FALL);
	//set_bit(DDRB, CEC);
	enable_cec();
	
	// Pin change interrupt (PCINT0)
	set_bit(PCMSK, SDA);
	//enable_i2c();
	
	// Enable timer with prescaling factor 64
	TCCR0B = 3;
	
	clock_prescale_set(clock_div_1);
	// Clock prescaling factor 1 (8 MHz)
	//CCP = 0xd8; // Config Change Protection
	//CLKPSR = clock_div_1; // Clock prescaler select (default is 8)
	
	SP = RAMEND;
	DDRB = 0b1011;
	
	length = 0;
	cec_addr = CEC_DEFAULT;
	reg = 0;
	flags = 0;
	taken = 0;
	
	length = 5;
	buffer[0] = 0xaf;
	buffer[1] = 'T';
	buffer[2] = 'E';
	buffer[3] = 'S';
	buffer[4] = 'T';
	
	for(;;) {
		sei();
		//sleep_cpu();
		
		//if(get_flag(FLAG_CEC)) {
		//	disable_i2c();
			// Abort if it takes too long to prevent the CEC bus from
			//  locking i2c indefinitely
			set_error_timeout(TICKS_BIT*16*3);
			enable_error_timeout();
			
			cec_write();
			
			disable_error_timeout();
		//	enable_i2c();
		//}
	}
	unreachable();
}
