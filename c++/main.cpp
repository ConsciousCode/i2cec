#include "common.hpp"

#include <avr/interrupt.h>
#include <avr/sfr_defs.h>
#include <avr/wdt.h>
#include <avr/sleep.h>
#include <avr/power.h>
#include <util/delay_basic.h>

//#include "cec.cpp"
//#include "i2c.cpp"

extern "C" __attribute__((naked)) void main() {
	// Disable unused modules
	ACSR |= _BV(ACD); // Analog Comparator Disable
	power_adc_disable();
	DIDR0 |= _BV(RESET); // Digital Input Disable
	
	// Allow buses to float high in input mode
	PUEB = _BV(SDA) | _BV(CEC) | _BV(SCL); // Pull-Up Enable
	
	// Pull line low when in output mode
	//PORTB = 0;
	
	// Sleep mode
	//set_sleep_mode(SLEEP_MODE_IDLE);
	sleep_enable();

	// Default to all input ("free")
	//DDRB = 0;
	
	// Initialize program state
	
	taken_vec = 0;
	length = 0;
	cec_addr = CEC_DEFAULT;
	
	// Set up interrupts
	
	// External interrupt (INT0)
	set_int0_mode(FALL);
	//TCCR0B = 1
	//enable_int0();
	
	// Pin change interrupt (PCINT0)
	PCMSK = _BV(SDA);
	enable_pcint0();
	
	// Clock prescaling factor 1 (8 MHz)
	clock_prescale_set(clock_div_1);
	
	for(;;) {
		sei();
		sleep_cpu();
	}
}
