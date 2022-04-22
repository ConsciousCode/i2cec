Anyone's free to use however they see fit. I only wrote
this because I wanted my TV-monitor to turn on/off with
my computer's wake cycles, and I was too stubborn to use an ATtiny85
with premade libraries.

## Why
I bought a cheap ONN TV from Walmart to act as a monitor
for my ~~laptop~~ desktop computer and realized
far too late that displaying over HDMI means that the TV
can't be powered on when it comes out of sleep mode. That
means *I have to press the ON button when it turns off
because the signal goes dead too long*! Luckily, this
travesty is easy to correct, as even this cheapo TV
supports CEC... But alas, most GPUs do not... for some
reason. If I could just send CEC signals to my TV, I
could get it to interpret any signal that could be sent
from a remote control, to include the power-on/off signal.

There do appear to be HDMI-CEC adapters online, though
it's extremely unclear how they work (USB?) and they cost
a whopping $50. Not even my poor bruised turning-on finger
can withstand such robbery. So instead, I bought a pack of
15 $0.35 ATtiny10s (6 pins!) and a cheap $4 HDMI dongle to
splice it in.

HDMI contains wires for both of these buses, meaning it's
possible to write a simple bridging firmware to convert
i2c messages (we can write the driver later) into CEC
messages, effectively giving total control over the
display without even using another input method. What's
more, CEC only requires a maximum of 16 bytes of SRAM for
a message buffer, as all messages must be shorter than
that, and optionally a 2-byte bitfield recording taken
addresses. This fits perfectly within ATtiny10's spartan
32 B of SRAM.

## Technical

### i2c
i2c is a well-known multi-master multi-slave bus protocol
operating on two wires, sda and scl. HDMI uses an i2c bus
to perform EDID (basically check what resolutions are
supported), but this is almost always a fully-functional
i2c bus with just one slave, the display (in my case, the one monitor
has two addresses and there's some unknown device 0x3a)

Except for START and STOP, SDA will only change when SCL is low

```
0: SDA: ‾\___
   SCL: \_/‾\

1: SDA: _/‾‾‾
   SCL: \_/‾\

<: SDA: _/‾\_ (START)
   SCL: \_/‾\

>: SDA: ‾\_/‾ (STOP)
   SCL: \_/‾\
```

Message:
* START
* u7 dst
* bit rw (0 = w)
* repeated
  - byte
  - bit ack
* STOP

Note that more than one START can come before STOP, which is called a
"start repeat" and is used to chain related information. Usually,
this is for writing a register address, then switching to read mode
to read the response.

### CEC
"CEC" stands for "Consumer Electronic Communication" and
is a single-wire shared bus (no masters or slaves) with
extremely low bandwidth (~417 B/s) meant for simple
communication between devices connected via HDMI, even if
connecting devices are powered off. Mostly, this allows a
single remote control to control several devices, as the
IR receiver can submit a broadcast message to the bus, and
to notify the display when a device is being powered on,
allowing it to "smartly" switch inputs to the new device.

```
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
```

Sample after 1.05 ± 0.2 ms and watch for next bit after 1.9 ± 0.15 ms

Byte:
* byte payload
* bit eom
* bit ack (writable)

Message:
* START
* byte{0, 16}

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

### Pinout
```
     ┌─────┐
SDA ─┤1▀  6├┐ (or NC or dirty)
GND ─┤2   5├┴ Vcc
SCL ─┤3   4├─ CEC
     └─────┘

HDMI Pinout:

    <────────o
╷────────────────╷
│_  ▃▉▀▀======  _│
  ╲____________╱

Where === is a hole with contacts facing inwards (socket view)

o	D2+
│		D2/
│	D2-
│		D1+
│	D1/
│		D1+
│	D0+
│		D0/
│	D0-
│		C+
│	C/
│		C-
│	CEC		*4
│		<>
│	SCL		*3
│		SDA	*1
│	GND		*2
│		Vcc	*5,6
v	HPD
```

### Interrupts and timers
Originally I used INT0 for SCL and PCINT0 for CEC, thinking that I
would execute the interrupt every clock tick - nope! The ATtiny10 is
waaaay too slow for that, which took ages to realize because it just
looked like it was spitting out garbage from how much lag it had.

Instead, PCINT0 is tied to SDA and INT0 to CEC. Some assembly in the
IVT guarantees PCINT0 will only be fired when SCL is high, indicating
a START/STOP condition. From there, we remain in the interrupt and
handle timing by using simple poll loops provided by avr/io.h which
only end up looping a few times anyway. Even after this massive
improvement in response time, it was still very easy to desynchronize
if I wasn't careful. CEC on the other hand could fire INT0, then
reuse the interrupt to synchronize to falling edges of each successive
bit. 99% of the time is spent in sleep mode waiting for a timer to go
off, that's just how slow CEC is. This could also be handled by poll
loops, but I had plenty of program space left and an unused timer,
plus ideally this would be as low-power as physically possible.

I used TIM0_CMPA for handling normal timing and TIM0_CMPB as a kind of
watchdog (IIRC the actual wdt was either too slow or too low res) for
when the CEC bus took too long to respond.

### Event loop
The meat of the logic is contained within interrupts, but some was
put into the sleep/event loop at the end of main which waits for the
buffer to be written to, then dedicates computation to writing to the
CEC bus after i2c is done. This is the most intuitive way to implement
it, as we only know when i2c is done when a STOP condition is
detected asynchronously, and not all messages will require writing to
the CEC bus.

### Project structure
C code is split between headers for sharing symbols for my IDE, 3 C
files cec.c, i2c.c, and main.c which are included together into a
single compilation unit (to avoid problems with cross-unit
optimization and the bugginess of the `-fwhole-program` flag which
often generated out-of-range `rjmp` calls), and head.S which defines
the IVT. There are a lot of cheeky hacks to make everything work
well. Just to list a few,
* Unused IVT entries are used for assembly stubs
* Some functions are written to encourage the compiler to generate
   multiple entries (eg body of one falls through to the next)
* Most variables are defined as global registers
* Interrupt nesting is carefully managed for detecting START/STOP
   conditions and reusing the CEC interrupt for timeouts
* Virtual register memory is implemented by a kind of manual switch
   statement with fallthrough and rcall to common code in the same
   function
* Special compiler flags to reduce interference (eg `-fnostartfile`)
* Lots and lots of inline assembly for when C just can't handle it
* Macro black magic to make code cleaner, eg `if_T()`

## Project history
This project has been a long time coming because there's a lot of
complicating issues. Mostly it's been a learning experience for the
conventions of i2c devices, timing, hardware, and logic analysis -
I'd get stuck on something like timing synchronization throwing off
the logic, then coming back a few weeks later completely revise the
protocols to be better in line with my understanding of i2c
conventions. A big one was realizing that while i2c supports my
earlier protocol of commands and copying into the buffer, tools like
`i2cdump` create strange glitches because they expect a register-based
protocol. I adjusted this a few times before deciding on just making
a virtual memory space for registers, which turned out to have simpler
code anyway.

I also flip-flopped between combinations of C, C++, and assembly
multiple times. First was a restricted C++ which produced a binary too
big for the program ROM. Then pure assembly, but I ended up
implementing so many macros and control structure that I was able to
rewrite the same thing in C again. Then I tried adding C++ features in
using dead code elimination and classes to represent assembly stubs
to treat unaddressable structures as registers (eg a T class for the T
register which features prominently in all the bit banging). This
caused me to fight with the compiler, so I finally refactored it all
into C and a little bit of assembly with supplemental macros to make
the difference (eg `if_T` to represent `brts` which in C++ was `if(T)`
using the `bool` operator).

There were a lot of quirks that I had to work around, particularly
when it came to `avr-gcc`. The output binary always had the correct
instruction subset, but oftentimes failed to produce optimal code. It
was clear that there wasn't any special optimizations for T10, just
unsupported features being disabled. Thus, trial and error was
required, compiling code and checking the disassembly to make sure
it's correct. For a while I kept getting a segfault whenever I used avr1, which ended up being because the compiler doesn't like setting `r18` or `r19` as fixed registers (the avr-gcc ABI spec says they're call-saved). For SEO, the error was "internal compiler error: in init_reg_sets_1, at reginfo.c:439"

## How to use
In short, flash an ATtiny10 with the firmware, attach the
pins to the wires in a donor HDMI cable, and from there it
should respond to address 0x71 on the i2c bus. The pins to
connect are:
* Pin1 = CEC
* Pin2 = GND
* Pin3 = SDA
* Pin4 = NC (or dirty buffer signal but disable the RESET fuse first)
* Pin5 = Vcc
* Pin6 = SCL

The donor HDMI adapter I used can be found [here](https://www.amazon.com/gp/product/B079ZPK4V2/ref=ppx_yo_dt_b_asin_title_o03_s00?ie=UTF8&psc=1) - it
came as a pack of 2, which was very handy to practice on
the first one and accidentally cut a few wires. If you use
this, I recommend removing the outer casing of the female
end with a scalpel down the edges, then only cutting the
plastic filling around the connector's pads, thus keeping
the fragile wires safe and in place. A bit of the cable
shielding will poke out, this can be kept in place with a
bit of hot glue. I filed safe parts of the plastic filling
to make room for the ATtiny10 and connecting wires and
closed it up with simple shrink tubing.

### Configuration
The main things to configure are the i2c address, identity string,
and dirty buffer signalling. 10-bit i2c addresses are supported by
setting `I2C_ADDR` to something larger than `0x7800`, which is the
10-bit address for 0 (including the `11110` prefix which identifies
10-bit addressed devices). The identity string is just vanity and for
debug purposes, set it to anything you want. The dirty buffer signal
sets the given pin high when the CEC buffer has been written to from
the CEC bus but not yet read.

## Drivers
I'll get to writing a driver later. Once I get it working,
it'll be enough to write some hacky script to write the
right commands into the message buffer and hook that into
systemd.

## Registers
Here's a map of the i2c registers:

   0 1 2 3 4 5 6 7 8 9 A B C D E F
00 I I I I I I I I I I I I A T T L
10 B B B B B B B B B B B B B B B B

* I = (R ) human-readable identification string (default "i2cec")
* A = (RW) 4-bit CEC address (0xF to record all)
* T = (R ) 16-bit vector of addresses taken on the CEC bus
* L = (R ) length of buffer (only lower 4 bits used)
* B = (RW) 16-byte buffer. Read gets the last CEC message addressed to
   us, write is buffered and written to the CEC bus when the write is
   done. Bytes after L aren't overwritten and may contain leftover
   junk

All other registers are reserved and will NACK when their register
address is written. The register will auto-increment for valid
messages. To write to the buffer, start with its address and then
write up to 16 bytes which will be written to CEC after STOP. It's an
error to begin writing at any point after the first address and it
will NACK as if that register is readonly. Once the message is
written, length will reset to 0. CEC messages addressed to us will
also fill the buffer - note that if you write without reading, that
message is lost.

The CEC address register can write any value, though it will be
truncated to the least significant 4 bits. The address of 0xF is
special in that it will record *every* message on the CEC bus rather
than just things addressed to it, since 0xF is for "broadcast". Also,
i2cec does not format the CEC message at all - it is written as-is,
so the src, dst, and cmd fields need to be formatted correctly.

Reading from the CEC buffer is intended to be a 17-byte read message
starting at the length register. This has no side effects other than
clearing the dirty pin state (if applicable) and allows simple code to
grab everything in one go.

Sample script to poll:
```bash
i2ctransfer $BUS w1@$ADDR 0x0f r17
```

## Challenges
Firstly I had to make a bunch of prototype boards for flashing and
splicing into HDMI - one of the dongles got wires hanging out to a
pin header, which attached to a custom 5-wire cable, which attached
to a breakout board, which had an IC socket which received a tiny
6-pin board with a debugging ATtiny10 soldered on. The programmer
was basically just a handmade TPI board with IC socket and a pin
header to connect to the USBasp.
Any time I needed to make a change, remove it from one socket, put it
on the other, run commands, rinse and repeat. Between all this was a
breadboard to splice all the wires into a logic analyzer as well,
since I didn't have the foresight to bake that into one of the boards.

Let me tell you, interpreting logic analyzer signals with an
environment this restricted is *really* hard, mostly because of how
*asynchronous* everything is. 90% of my code is executing in
interrupts which are carefully enabled and disabled to avoid stepping
on each other (or even nesting interrupts!) and I found out after
weeks of tearing my hair out that all the interrupts have a flag
register for when an interrupt occurs while that interrupt is
disabled, and when sei is enabled those are executed in order which
made everything behave extremely erratically.

Next, there's the difficulties with actually debugging this thing.
Normally when I debug software, I sprinkle all sorts of debug messages
to tell me where and when and in what state things are called. But
here? I got one bit to work with if I disabled half the code.
Conceivably I could hack up a kind of mini-UART and feed that into the
logic analyzer, but while debugging i2c this is a non-starter since
it's just barely fast enough to reply in the first place. Even just
writing to CEC as a direct output would desynchronize i2c sometimes.

## External links
So I stop forgetting them
* [avr1 spec](http://ww1.microchip.com/downloads/en/DeviceDoc/atmel-8127-avr-8-bit-microcontroller-attiny4-attiny5-attiny9-attiny10_datasheet.pdf)
* [inline assembler cookbook](https://www.nongnu.org/avr-libc/user-manual/inline_asm.html)
* [avr-gcc ABI](https://gcc.gnu.org/wiki/avr-gcc)
* [reginfo.c](https://code.woboq.org/gcc/gcc/reginfo.c.html)
  - This is how I finally figured out why `avr-gcc` kept segfaulting
* [avr-gcc v10.1.0](https://blog.zakkemble.net/avr-gcc-builds/)
  - The apt repo has 5.4
* [Metaprogramming custom control structures in C](https://www.chiark.greenend.org.uk/~sgtatham/mp/)
  - I used these techniques to build the `if_T()` macro so as to wrap
     the ugliness of using `brtc`/`brts` and labels