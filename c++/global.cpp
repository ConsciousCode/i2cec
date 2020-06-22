#include "global.hpp"
#include <avr/pgmspace.h>

Message msg;
uint16_t taken_vec;

const char id_str[8] PROGMEM = IDENT;