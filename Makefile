CC = avr-gcc
OBJCPY = avr-objcopy
MCU = attiny10
avrType = t10
prog = usbasp
NAME = i2cec
CFLAGS = -std=c++11 -Os
CFLAGS += -nostartfiles -nodefaultlibs -ffreestanding -mmcu=$(MCU)

.PHONY: clean help hex program default size
default: clean object hex size

debug: clean
	$(CC) $(DFLAGS) $(SRC).S -o $@

help:
	@echo 'clean	Clean up object files' \
	@echo 'help		Show this text.' \
	@echo 'hex		Create all hex files for flash, eeprom and fuses.' \
	@echo 'object	Make $(NAME).o' \
	@echo 'program	Do all programming to controller'

size: $(NAME).o
	avr-size $^
.PHONY: size

$(NAME).o: head.S main.cpp
	$(CC) $(CFLAGS) $^ -o $@

object: $(NAME).o
.PHONY: object

%.hex: %.o
	$(OBJCPY) -j .text -j .data -O ihex $^ $@

hex: $(NAME).hex
.PHONY: hex

program: i2cec.hex
	avrdude -p$(avrType) -c$(prog) -v -U flash:w:$^
.PHONY: program

clean:
	rm -f *.o *.hex
.PHONY: clean
