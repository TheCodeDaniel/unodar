// Check of the avr8js runner's pin I/O (tool/avr_runner/run.mjs --pin, --pin-log). Hand-written C++, run by
// runtime_fidelity_test.dart. D2 is a button to GND (INPUT_PULLUP), D3 a plain input the test drives HIGH, A1 a
// plain input nobody drives, and D13 an output that mirrors D2. Prints the levels it reads, then DONE at 400 ms.
#include <Arduino.h>

int last = -1;

static void level(const __FlashStringHelper *name, int value) {
  Serial.print(name);
  Serial.print(value);
}

void setup() {
  Serial.begin(115200);
  pinMode(2, INPUT_PULLUP);
  pinMode(3, INPUT);
  pinMode(A1, INPUT);
  pinMode(13, OUTPUT);
  level(F("boot D2="), digitalRead(2));
  level(F(" D3="), digitalRead(3));
  level(F(" A1="), digitalRead(A1));
  Serial.println();
}

void loop() {
  const int d2 = digitalRead(2);
  digitalWrite(13, d2);
  if (d2 != last) {
    last = d2;
    level(F("D2="), d2);
    Serial.print(F(" at "));
    Serial.println(millis());
  }
  if (millis() >= 400) {
    level(F("end D3="), digitalRead(3));
    level(F(" A1="), digitalRead(A1));
    Serial.println();
    Serial.println(F("DONE"));
    while (true) {
    }
  }
}
