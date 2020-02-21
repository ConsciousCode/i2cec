/**
 * End-user configuration and interfacing
**/

#define __AVR_ATtiny10__ 1
#include <avr/io.h>

// i2c address, mostly arbitrary
#define I2C_ADDR 0x71

// Special address for device-id
#define DEV_ID 0x74

// Content to be read for device-id
// (12-bit manufacturer, 9-bit part id, 3-bit die)
// 00d=Atmel, ff+0b1 (all set, custom?), 0b000 (we'll say die revision 0)
#define DEVID_DATA 0x00dff4 

#ifdef DIRTY_PIN
	#define DIRTY_CONFIG "d"
#else
	#define DIRTY_CONFIG "-"
#endif

// Readonly firmware identity/version
#define VERSION "i2cec1:" DIRTY_CONFIG

// 0x15 is CEC's "no address" or broadcast address
#define CEC_ADDR_DEFAULT 0x15

// Pin assignments
#define SCL PORTB2
#define SDA PORTB1
#define CEC PORTB0

// Commands

/*
 * There are two types of commands: load and action
 * Load commands work like normal i2c registers and dump data to the buffer
 * Action commands have side effects and might not even result in data to
 *  read, so to protect against naive scanners which try to "read" these,
 *  and thus initiate unintended side effects, these commands require an
 *  extra byte to be written - the value depends on the command, and some
 *  may outright ignore it (although it still must be written)
 * 
 * Action commands have a set MSB while load commands don't.
 */

#define LOAD 0x00

#define NOP (LOAD + 0) // Do nothing (dummy command)
#define LOAD_ID (LOAD + 1) // Emit a readonly string for identification
#define LOAD_TAKEN (LOAD + 2) // Load the vector of taken CEC addresses
#define LOAD_LENGTH (LOAD + 7) // Load the length register
#define LOAD_GBF (LOAD + 3) // Load the gbf register
#define LOAD_I2C (LOAD + 4) // Load the i2c address
#define LOAD_CEC (LOAD + 5) // Load the CEC address
#define LOAD_ADDR (LOAD + 6) // Load an arbitrary address into the buffer, reading `length` bytes

#define ACTION 0x80

// Modify state
#define SET_LENGTH (ACTION + 0) // Set length=HI(cmd) for debugging
#define RESET (ACTION + 1) // Reset the microcontroller
#define CEC_SEND (ACTION + 2) // Write the buffer to the CEC bus
#define SET_ADDR (ACTION + 3) // Set CEC address
#define TOGGLE_MON (ACTION + 4) // Toggle monitor mode (record CEC regardless of who sent it)
#define TOGGLE_DEBUG (ACTION + 5) // Toggle debug mode

// Whether or not to use pin 3 to indicate a "dirty" buffer
// Note that this is optional, comment to remove the feature
//#define DIRTY_PIN PORTB3
