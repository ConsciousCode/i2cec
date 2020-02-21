This document is to help me keep all the information together in one
place so I don't forget later.

## CEC protocol

CEC is a one-wire bidirectional serial bus. Logic bits are
determined by the timing of low-high pulses. 

    2.4 ± 0.35 ms
   |-------------|
0: \_________/‾‾‾
      ^--- 1.5 ± 0.2 ms

1: \____/‾‾‾‾‾‾‾‾
      ^--- 0.6 ± 0.2 ms

        4.5 ± 0.2 ms
       |-----------------------|
START: \_______________/‾‾‾‾‾‾‾
          ^--- 3.7 ± 0.2 ms

Sample after 1.05 ± 0.2 ms and watch for next bit after 1.9 ± 0.15 ms

Byte:
* bit8 payload
* bit1 eom
* bit1 ack (writable)

Message:
* START
* byte[0:16]
  - byte[0]
    * bit4 src
    * bit4 dst
  - byte[1] cmd (opt)

Addresses:
* 0  TV
* 1  Recording device 1
* 2  Recording device 2
* 3  Tuner 1
* 4  Playback device 1
* 5  Audio system
* 6  Tuner 2
* 7  Tuner 3
* 8  Playback device 2
* 9  Playback device 3
* 10 Tuner 4
* 11 Playback device 4
* 12 Reserved
* 13 Reserved
* 14 Free
* 15 Unregistered/Broadcast

## i2c protocol
Two-wire bidirectional serial bus. Operates with pins SDA and SCL

### Physical layer

Except for START and STOP, SDA will only change when SCL is low

0: SDA: ‾\___
   SCL: \_/‾\

1: SDA: _/‾‾‾
   SCL: \_/‾\

<: SDA: _/‾\_ (START)
   SCL: \_/‾\

>: SDA: ‾\_/‾ (STOP)
   SCL: \_/‾\

Message:
* START
* bit7 dst
* bit1 rw (0 = w)
* byte[]
* STOP

### i2cec commands

Communication with i2cec is done primarily through i2c which
may result in data being written to the CEC bus. If the packet
is read, i2cec will write the contents of its buffer back
to master. If the packet is write, the first byte is the command
and the rest is its payload. i2cec is fault-tolerant and can
safely ignore overly long payloads. Operations are usually done
on the internal 16-byte buffer, but a few mode toggles are also
included.

Logic for address negotiation and CEC message formatting is offloaded
to master.

Commands: (see config.h for values)
* *RW_BUFFER:* No special setup, prepare to read/write to the buffer
* *LOAD_TAKEN:* Load the `taken` vector into the buffer
  - The `taken` vector is a 16-bit vector indicating which addresses
    have been taken on the CEC bus
* *CEC_SEND:* Write the buffer to the CEC bus
* *SET_ADDR:* Set CEC address (for reading from CEC)
* *TOGGLE_MON:* Toggle monitor mode
  - Monitor mode loads all CEC messages into the buffer, to be read
    by the master. Unread messages are overwritten.
  - If monitor mode is not active, only messages with our address
    are recorded
* *TOGGLE_DEBUG:* Toggle debug mode
  - Currently unused

## Program design
### Interrupts and timers
INT0 in pin-change mode for SCL is used to drive i2c reading and
writing. Reads occur on the rising edge, writes on the falling edge
(if in the appropriate mode). At the moment, this interrupt is
always active but exits early when it's in the IDLE state, as it's
waiting for the START condition which is mediated by SDA.

PCINT0 is used for CEC read events and the i2c START/STOP conditions,
which occur when SDA changes while SCL is high.

TIM0_CMPA is only used when writing to the CEC bus, including an ACK
during reading. Only CEC requires specific timing and CEC reads
determine logic values by comparing the timer between pin changes.

### Event loop
All logic in i2cec is contained within interrupts. After startup,
the main program enters an infinite loop of `sleep` instructions.

### Serial FSM
Interrupts are asynchronous by nature, and both buses are serial. To
help with logic, a `state` register is defined which keeps an
arbitrary enumerated integer representing a "state" within an FSM.
This is shared between logic for both buses, since they have a lot
in common. The states are:
* *IDLE:* Ignoring the bus / don't want arbitration (both)
* *START:* Reading the START condition of CEC (CEC)
* *EOM:* Reading the CEC EOM bit (CEC)
* *WHO:* Reading the address component (both)
* *CMD:* Reading the i2c command (i2c)
* *WAIT:* Waiting for opportunity to arbitrate on CEC (CEC)
* *DATA:* Reading data (both)

### Registers
Registers are used as static globals and are never saved to the call
stack. These are:
* *gbf:* General/global bit field
  - *OLD_CEC:* Last read value of CEC
  - *OLD_SDA:* Last read value of SDA
  - *RW:* RW mode, 0 = write and 1 = read
  - *ACK:* Acknowledge inverts RW for one bit
  - *HILO:* CEC bit high/low state, low = 0 and high = 1
  - *I2CEC:* Which bus is active, CEC = 0 and i2c = 1
  - *MONITOR:* Monitor mode flag
  - *DEBUG:* Debug mode flag (unused)
* *state:* FSM state
* *data:* Byte buffer for reading/writing to either bus
* *nbits:* Number of bits in the byte buffer `data`
* *tmp:* Miscellaneous destructive use
* *length:* Length of the message buffer in bytes
* *cec_addr:* 4-bit address on the CEC bus

The X register is always 0 because that is the offset of the
message buffer, and is aliased as `__zero_reg__` as a way
to easily clear I/O registers without an intermediate `ldi tmp, 0`

The Y register holds the `taken` vector, address flags are stored
as little-endian (eg address 0 sets r8.0).

The Z register and r23-r25 are unused (total of 5, could be used
for future optimizations)

### Subroutines
There are only 2 subroutines thus far. Neither take stack parameters
or push/pop registers. The only use of the stack is for the return
address.

### Macros
Some idioms are so common that macros were created to simplify code:
* *DONE/done:* Execute `reti` either directly or as a jump
* *HOLD:* Hold a pin low
* *FREE:* Free a pin (allows it to go high)
* *enable_timer:* Enable TIM0_CMPA for CEC writing
* *disable_timer:* Disable TIM0_CMPA
* *clear_timer:* Set the internal timer back to 0
* *set_timeout:* Set the timeout for the CEC write timer
* *set_flag:* Set a flag in the GBF
* *clear_flag:* Clear a flag in the GBF
* *if_unset:* Jump if GBF flag is unset
* *if_set:* Jump if GBF flag is set
* *if_low:* Jump if pin is low
* *if_high:* Jump if pin is high
* *if_state:* Jump if state is a value

## Race conditions
CEC and i2c bus interactions are mutually exclusive, in large part
because they share a `state` register which acts like a FSM.
Whichever message starts first is the one which will be processed.
Wherever possible, messages will be ended early and ignored which
frees i2cec to process the other bus. In general this shouldn't
be a problem because CEC is such a slow protocol, but it may be
necessary to handle this edge case.

## Extras
As an extra feature, the "dirty pin" can be enabled in config.h which
goes high when the CEC bus writes to the message buffer but
has yet to be read by the i2c master. This may be useful for making
an interrupt to read from the buffer.