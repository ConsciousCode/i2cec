CC = avr-gcc
OBJCPY = avr-objcopy
MCU = attiny10
avrType = t10
prog = usbasp
CFLAGS = -g

#CFLAGS = -mmcu=$(MCU) -maccumulate-args -mrelax -msp8 -mtiny-stack
#CFLAGS += -ffixed-20 -ffixed-21 -ffixed-23 -Os -g -fdata-sections
#CFLAGS += -nostartfiles -nodefaultlibs -ffreestanding -finline
#CFLAGS += -std=c++17

.PHONY: clean help hex program default size
default: clean size
help:
	@echo 'clean	Clean up object files' \
	@echo 'help		Show this text.' \
	@echo 'hex		Create all hex files for flash, eeprom and fuses.' \
	@echo 'program	Do all programming to controller'

size: i2cec.hex
	avr-size $^
.PHONY: size

i2cec: main.S
	$(CC) $(CFLAGS) $^ -o $@

i2cec.hex: i2cec
	$(OBJCPY) -j .vectors -j .text -O ihex $^ $@

hex: i2cec.hex
.PHONY: hex

program: hex
	avrdude -p$(avrType) -c$(prog) -v -U flash:w:i2cec.hex
.PHONY: program

clean:
	rm -f *.o *.hex i2cec
.PHONY: clean
