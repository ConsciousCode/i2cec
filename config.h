#define I2C_ADDR 0x71

#define SCL PORTB2
#define SDA PORTB1
#define CEC PORTB0

#define READ 1
#define WRITE 0
#define LO 1
#define HI 0

#define CLOCK_HZ 8000000
#define CLOCK_DIV 1024
#define TIMER_HZ (CLOCK_HZ/CLOCK_DIV)

// Times are in microseconds 
#define JIFFY (1000000/TIMER_HZ)
#define TIME_1 600
#define TIME_0 1500
#define TIME_BIT 4500
#define TIME_E 150 // Allowed error
#define TIME_START0 3700 // CEC START low component
#define TIME_START1 600 // CEC START high component

// Measured in jiffies
#define JIFFY_BIT (TIME_BIT/JIFFY)

#define JIFFY_1_LO (TIME_1/JIFFY)
#define JIFFY_1_HI (JIFFY_BIT - JIFFY_1_LO)

#define JIFFY_0_LO (TIME_0/JIFFY)
#define JIFFY_0_HI (JIFFY_BIT - JIFFY_0_LO)

#define JIFFY_DATA_MID ((JIFFY_1_LO + JIFFY_0_HI)/2)

#define JIFFY_E (TIME_E/JIFFY)

#define JIFFY_START_LO (TIME_START0/JIFFY)
#define JIFFY_START_HI (TIME_START1/JIFFY)
#define JIFFY_START_MID ((JIFFY_START_LO + JIFFY_START_HI)/2)
#define JIFFY_START (JIFFY_START_LO + JIFFY_START_HI)