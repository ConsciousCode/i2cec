CC = avr-gcc
OBJCPY = avr-objcopy
OBJDUMP = avr-objdump
MCU = attiny10
avrType = t10
prog = usbasp
CFLAGS = #--verbose

CFLAGS += -Os
CFLAGS += -mmcu=$(MCU) -nostartfiles -nodefaultlibs -ffreestanding
# length(18), data(19), cec_addr(20), reg(21), flags(22), taken(26:27
CFLAGS += -ffixed-20 -ffixed-21 -ffixed-22 -ffixed-26 -ffixed-27
CFLAGS += -fwhole-program -msp8 -mtiny-stack# -fno-inline

.PHONY: clean help hex program default size
default: clean size
help:
	@echo 'clean    Clean up object files'
	@echo 'help     Show this text'
	@echo 'asm      Make just the assembly for debug'
	@echo 'hex      Create all hex files for flash, eeprom and fuses'
	@echo 'object   Compile just the .o file for relocation errors'
	@echo 'program  Do all programming to controller'
	@echo 'size     Print the size of the compiled binary'
	@echo 'dump     Show disassembly for debug'
	@echo 'dump-hex Show dis for the file to be flashed'

size: i2cec.hex
	avr-size $^
.PHONY: size

i2cec: head.S main.c
	$(CC) $(CFLAGS) $^ -o $@

i2cec.hex: i2cec
	$(OBJCPY) -j .vectors -j .text -O ihex $^ $@

asm: main.c
	$(CC) $(CFLAGS) -S $^ -o dout.s
.PHONY: asm

object: main.c
	$(CC) $(CFLAGS) -c $^ -o dout.o

hex: i2cec.hex
.PHONY: hex

program: hex
	avrdude -p$(avrType) -c$(prog) -v -U flash:w:i2cec.hex
.PHONY: program

dump: i2cec
	$(OBJDUMP) -D $^ | less
.PHONY: dump

dump-hex: i2cec.hex
	$(OBJDUMP) -mavr:1 -D $^ | less
.PHONY: dump-hex

clean:
	rm -f *.o *.hex i2cec dout*
.PHONY: clean
