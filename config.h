#ifndef CONFIG_H
#define CONFIG_H

/**
 * End-user configuration and interfacing
**/

// Build 10-bit i2c address using prefix and bitmask
#define I2C_10BIT(addr) (0x7800|(addr)&0x3FF)

// i2c address, mostly arbitrary
#define I2C_ADDR 0x71

// Example 10-bit address
//#define I2C_ADDR I2C_10BIT(0x143)

// Readonly firmware identity/version, at most 12 characters
#define IDENT "i2cec"

// Total size of the identity registers, excess filled with 0s
#define IDENT_SIZE 12

// 0x15 is CEC's "no address" or broadcast address
#define CEC_DEFAULT 0x15

// Size of the interoperation buffer
#define BUFFER_SIZE 16

// Pin assignments
#define SDA 0
#define SCL 1
#define CEC 2
#define RESET 3

// Define this to enable dirty CEC buffer signalling on that pin
//#define DIRTY 3

// Registers

/**
 * 00-0B (R ) Null-terminated identity string
 *    0C (RW) 4 bit CEC address to auto-ACK (0 = disabled)
 * 0D-0E (R ) Taken address bit vector
 *    0F (R ) Length of buffer contents
 * 10-1F (RW) Interbus buffer
**/

#define REG_ID 0x00 // (R) Readonly identification string

#define REG_ADDR 0x0C // (RW) 4-bit CEC address to auto-ACK
#define REG_TAKEN_HI 0x0D // (R) 16 bit vector of taken addresses
#define REG_TAKEN_LO 0x0E
#define REG_LENGTH 0x0F // (R) Length of the buffer contents

#define REG_CEC 0x10 // (RW) The CEC bus

#endif
