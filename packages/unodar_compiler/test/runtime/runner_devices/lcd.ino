// Runner check (Phase 6 step 17): the HD44780 model of the avr8js runner. Hand-written C++ with LiquidCrystal 1.0.7,
// wired as in Arduino's examples (RS 12, E 11, D4-D7 on 5, 4, 3, 2): two rows of text, a cursor move, the cursor
// and blink flags, and a display shift.
#include <Arduino.h>
#include <LiquidCrystal.h>

LiquidCrystal lcd(12, 11, 5, 4, 3, 2);

void setup() {
  Serial.begin(9600);
  lcd.begin(16, 2);
  lcd.print("Hello, world!");
  lcd.setCursor(2, 1);
  lcd.print(42);
  lcd.cursor();
  lcd.blink();
  lcd.setCursor(0, 1);
  lcd.write('>');
  lcd.scrollDisplayRight();
  Serial.println("DONE");
}

void loop() {}
