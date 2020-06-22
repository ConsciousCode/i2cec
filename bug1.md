```c
volatile register gbf asm("18");
enum gbf_Flags {
	MONITOR,
	NEST,
	MINE,
	EOM,
	CMD,
	WHO
};

#define set_flag(flag) asm volatile("sbr %0, %1" :"+r"(gbf):"I"(flag))
#define clear_flag(flag) asm volatile("cbr %0, %1" :"+r"(gbf):"I"(flag))

void main() {
	set_flag(NEST);
	clear_flag(NEST);
}
```

Compiles to:
```asm
main:
	ori 18, 0x01 ; Incorrect behavior!!
	andi 18, 0xFE
```

Should be:
```asm
main:
	sbr 18, 1
	cbr 18, 1
```

Or:
```asm
main:
	ori 18, 0x02
	andi 18, 0xFD
```