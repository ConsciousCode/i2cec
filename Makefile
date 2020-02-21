CC = avr-gcc
OBJCPY = avr-objcopy
MCU = attiny10
avrType = t10
prog = usbasp
SRC = main
CFLAGS = -std=c++11 -Os
CFLAGS += -nostartfiles -nodefaultlibs -ffreestanding

.PHONY: clean help hex object program default size
default: clean object hex size

help:
	@echo 'clean	Clean up object files' \
    @echo 'help		Show this text.' \
    @echo 'hex		Create all hex files for flash, eeprom and fuses.' \
    @echo 'object	Create $(SRC).o' \
    @echo 'program	Do all programming to controller


size:
	avr-size $(SRC).o

object: $(SRC).o
%.o: %.S
	$(CC) -mmcu=$(MCU) $(CFLAGS) $^ -o $@

hex: $(SRC).hex
%.hex: %.o
	$(OBJCPY) -j .text -j .data -O ihex $^ $@

program:
	avrdude -p$(avrType) -c$(prog) -v -U flash:w:$(SRC).hex

clean:
	rm -f *.o *.hex
