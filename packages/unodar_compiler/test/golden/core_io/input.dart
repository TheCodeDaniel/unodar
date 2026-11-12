import 'package:unodar/unodar.dart';

const int buttonPin = 2;
const int sensorPin = A0;
int lastToggle = 0;
bool ledOn = false;

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(buttonPin, INPUT_PULLUP);
}

void loop() {
  // analogRead returns a 16-bit C++ int: the product must still be computed in 32 bits.
  final level = analogRead(sensorPin);
  final scaled = analogRead(A1) * 100;
  final percent = scaled ~/ 1023;
  analogWrite(6, level ~/ 4);
  analogWrite(5, percent);

  // millis() is an unsigned long in C++; as a Dart int the elapsed-time check works across the wrap.
  final now = millis();
  if (now - lastToggle >= 500 && digitalRead(buttonPin) == LOW) {
    lastToggle = now;
    ledOn = !ledOn;
    digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
  }

  final start = micros();
  final pressed = digitalRead(buttonPin) == HIGH;
  if (pressed) {
    delay(1);
  }
  final elapsed = micros() - start;
  if (elapsed > 2000 || analogRead(A5) < 0) {
    digitalWrite(LED_BUILTIN, LOW);
  }
  final mixed = analogRead(A2);
  analogWrite(3, mixed ~/ 4 + mixed % 4 - analogRead(A3) % 2);
}
