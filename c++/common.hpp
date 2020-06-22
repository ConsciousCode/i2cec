#ifndef COMMON_H
#define COMMON_H

// Config first (has architecture defines)
#include "config.h"
#include "timing.h"

#include "arch.hpp"
#include "global.hpp"

#include <avr/interrupt.h>

void cec_write();

#endif
