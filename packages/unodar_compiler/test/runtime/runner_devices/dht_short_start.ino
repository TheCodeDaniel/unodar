// Runner check (Phase 6 step 19), negative control for the DHT22 model: a start signal of 0.5 ms, shorter than the
// datasheet's 0.8 ms, gets no answer, and the model reports it.
#include <Arduino.h>

void setup() {
  Serial.begin(9600);
  pinMode(2, OUTPUT);
  digitalWrite(2, LOW);
  delayMicroseconds(500);
  pinMode(2, INPUT_PULLUP);
  delayMicroseconds(300);
  Serial.println(digitalRead(2) == HIGH ? "no answer" : "answer");
  Serial.println("DONE");
}

void loop() {}
