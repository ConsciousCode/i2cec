/**
 * End-user configuration
**/

#include <avr/io.h>

// i2c address, mostly arbitrary
#define I2C_ADDR 0x71

// Pin assignments
#define SCL PORTB2
#define SDA PORTB1
#define CEC PORTB0

// Commands

/*
 * These commands act as the i2c "registers". A read
 *  session will write whatever is in the message buffer
 *  (up to 16 bytes) ending after length bytes. Write
 *  mode takes the lower nibble as the command to
 *  "execute". The higher nibble is only used for SET_ADDR,
 *  which sets the CEC address which the device will
 *  respond to.
 * 
 * Only the RW_BUFFER command expects data to follow it.
 */

#define RW_BUFFER 0 // No special setup, prepare to read/write to the buffer
#define LOAD_TAKEN 1 // Load taken into the buffer
#define CEC_SEND 2 // Write the buffer to the CEC bus
#define SET_ADDR 3 // Set CEC address (for reading from CEC)

// Note: Changing these only changes the calculation of
//  "jiffies" for timing, it won't affect the actual
//  timer control flags.
#define CLOCK_HZ 8000000
#define CLOCK_DIV 1024
