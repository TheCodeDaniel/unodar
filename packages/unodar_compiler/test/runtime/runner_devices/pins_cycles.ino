// Runner check (Phase 6 step 12): the cycle-stamped pin log. D13 goes high and low two cycles apart (sbi and cbi
// take 2 cycles each on the ATmega328P), far below the millisecond log's microsecond resolution.
#include <Arduino.h>

void setup() {
  Serial.begin(9600);
  DDRB |= 1 << 5;
  noInterrupts();
  PORTB |= 1 << 5;
  PORTB &= ~(1 << 5);
  interrupts();
  Serial.println("DONE");
}

void loop() {}
