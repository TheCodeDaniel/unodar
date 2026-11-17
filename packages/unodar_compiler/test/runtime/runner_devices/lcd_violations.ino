// Runner check (Phase 6 step 17): the HD44780 model's timing checks, each broken once on purpose after a correct
// begin(). Pins as lcd.ino: E is pin 11 (PB3), D4 is pin 5 (PD5).
#include <Arduino.h>
#include <LiquidCrystal.h>

LiquidCrystal lcd(12, 11, 5, 4, 3, 2);

void setup() {
  Serial.begin(9600);
  lcd.begin(16, 2);
  // 1. clear() without its 2 ms wait: the next instruction starts while the display is still clearing.
  lcd.command(0x01);
  lcd.write('A');
  delay(5);
  // 2. An E pulse of two cycles (125 ns, minimum 450 ns): the first half of a 4-bit transfer.
  PORTB |= _BV(3);
  PORTB &= ~_BV(3);
  delayMicroseconds(100);
  // 3. D4 changes while E is high: the second half.
  PORTB |= _BV(3);
  PORTD ^= _BV(5);
  delayMicroseconds(2);  // delayMicroseconds(1) is only 375 ns here, itself too short
  PORTB &= ~_BV(3);
  Serial.println("DONE");
}

void loop() {}
