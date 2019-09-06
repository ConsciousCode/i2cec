Anyone's free to use however they see fit. I only wrote
this because I wanted my TV-monitor to turn on/off with
my computer's wake cycles.

## Why
I bought a cheap ONN TV from Walmart to act as a monitor
for my ~~laptop~~ *ahem* desktop computer and realized
far too late that displaying over HDMI means that the TV
can't be powered down when it goes into sleep mode. That
means *I have to press the ON button when it turns off
because the signal goes dead too long*!!! Luckily, this
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
splice it in, along with a week of work learning AVR
assembly.

## Technical

### i2c
i2c is a well-known multi-master multi-slave bus protocol
operating on two wires, sda and scl. HDMI uses an i2c bus
to perform EDID (basically check what resolutions are
supported), but this is almost always a fully-functional
i2c bus with just one slave, the display. Quite a waste.

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

### Ok but so what?
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

Less fortunately, while bitbanging i2c is beautiful,
short, and purely PCINT-based, CEC is a time-based
protocol so it needs most of the PCINT subroutine, its
own timer interrupt, and a host of states for a FSM.

### Project structure
Everything is written in pure assembly. A first draft was
written in C/++ (C with cheats) but when compiled was over
4 kB, 4x the available program flash. A disassembly
revealed how frighteningly wasteful it was, so a lovingly
hand-crafted assembly was born, taking up around HALF the
available program flash with (almost) no ugly hacks.

main.S defines the basic layout: the interrupt vectors, a
separate assembly file for each IRF (together they were
around 600 lines of code, but it got somewhat confusing
when trying to find which one I was looking at) and
"main", which just sets up the SFRs and program state.
Each is #included directly via cpp, so there's only one
translation unit.

Macros are either in ALL CAPS or have underscores
in_them. Nothing fancy, just using better names for
otherwise unreadable registers. The only exception is
`done`. Early on I realized that instead of writing `reti`
for early exits, I could give it a label so I can refer to
it in branch/jump instructions. However, because it's used
so much, there's no one place in the code where every
`rjmp` can reach it. Instead, we have the `DONE` macro,
which emits a `reti` instruction and a unique label which
is assigned to `done`. Now `done` can be used to refer to
the last time we were able to use the `reti` instruction
by itself.

I made sure to keep the program flow as structured as
possible, even emulating blocks via indentation and
liberal commenting.

## How to use
In short, flash an ATtiny10 with the firmware, attach the
pins to the wires in a donor HDMI cable, and from there it
should respond to address 0x71 on the i2c bus. The pins to
connect are:
* Pin1 = CEC
* Pin2 = GND
* Pin3 = SDA
* Pin4 = NC
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

## Drivers
I'll get to writing a driver later. Once I get it working,
it'll be enough to write some hacky script to write the
right commands into the message buffer and hook that into
systemd.