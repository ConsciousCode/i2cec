CC = avr-gcc
MCU = attiny10
CFLAGS = -std=c++11 -Os -g
CFLAGS += -nostartfiles -nodefaultlibs -ffreestanding
FILES = init.S main.cpp

default: clean bridge
.PHONY: default

bridge:
	$(CC) -mmcu=$(MCU) $(CFLAGS) $(FILES) -o $@

asm:
	$(CC) -mmcu=$(MCU) $(CFLAGS) main.S -o $@

debug: clean
	$(CC) -mmcu=$(MCU) $(CFLAGS) -c main.S -o $@

clean:
	rm -f *.o asm
.PHONY: clean