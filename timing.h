/**
 * Macro definitions for the timing of the CEC bus
**/
#ifndef TIMING_H
#define TIMING_H

#define F_CPU 8000000 // ticks/second
#define PRESCALE 64 // Prescaling for timer ticks

// Times are in microseconds
#define TIME_1_LO 600 // Low time of CEC 1 bit
#define TIME_0_LO 1500 // Low time of CEC 0 bit
#define TIME_BIT 2400 // Total time of CEC bit
#define TIME_E 200 // Allowed error in CEC timing
#define TIME_START_LO 3700 // CEC START low component
#define TIME_START_HI 800 // CEC START high component 

// Note: Parens avoid a cpp overflow bug and int precision loss
#define JIFFY (F_CPU/1000000)/PRESCALE // Jiffy = ticks/us

// Measured in ticks
#define TICKS_BIT (TIME_BIT*JIFFY)

#define TICKS_1_LO (TIME_1_LO*JIFFY)
#define TICKS_1_HI (TICKS_BIT - TICKS_1_LO)

#define TICKS_0_LO (TIME_0_LO*JIFFY)
#define TICKS_0_HI (TICKS_BIT - TICKS_0_LO)

#define TICKS_E (TIME_E*JIFFY)

#define TICKS_START_LO (TIME_START_LO*JIFFY)
#define TICKS_START_HI (TIME_START_HI*JIFFY)
#define TICKS_START (TICKS_START_LO + TICKS_START_HI)

// How many ticks to wait before sampling
//  (By this point, 1's LO is done but 0's isn't)
#define TICKS_SAMP (TICKS_1_LO + TICKS_0_LO)/2

#endif
