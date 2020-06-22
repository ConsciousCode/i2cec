#ifndef CONFIG_H
#define CONFIG_H

/**
 * End-user configuration and interfacing
**/
#define __AVR_ATtiny10__
#define __SFR_OFFSET 0 // We don't want SFR offset
#include <avr/io.h>

// i2c address, mostly arbitrary
#define I2C_ADDR 0x71

// Readonly firmware identity/version
#define VERSION 1

#define IDENT "i2cec"

// 0x15 is CEC's "no address" or broadcast address
#define CEC_DEFAULT 0x15

// Size of the interoperation buffer
#define BUFFER_SIZE 16

// Pin assignments
#define SDA PINB0
#define SCL PINB1
#define CEC PINB2
#define RESET PINB3

// Registers/commands

#define REG_ID 0x00 // (R) Readonly identification string
#define REG_ADDR 0x01 // (RW) 4-bit CEC address to auto-ACK

#define REG_MAX REG_TAKEN

#define REG_CEC 0x0F // (RW) The CEC bus (Read is no-op)

#endif
