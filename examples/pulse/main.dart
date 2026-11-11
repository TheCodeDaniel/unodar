// Pulse: blinks the built-in LED (pin 13) in a short-long-short rhythm, then adds a growing number of extra short
// pulses (0 to 3) before each pause. Uses the Phase 2 language core: constants and a mutable global, functions with
// parameters and a return value, a for loop, a while loop, if/else, a local variable, and Dart's `%`.
//
// Build:   dart run packages/unodar_compiler/bin/unodar.dart build examples/pulse/main.dart -o out
// Compile: arduino-cli compile --fqbn arduino:avr:uno out/main
import 'package:unodar/unodar.dart';

const int ledPin = 13;
const int shortMs = 150;
const int longMs = 450;
int extra = 0;

void pulse(int ms) {
  digitalWrite(ledPin, HIGH);
  delay(ms);
  digitalWrite(ledPin, LOW);
  delay(shortMs);
}

int pulseLength(int i) {
  return i % 2 == 0 ? shortMs : longMs;
}

void setup() {
  pinMode(ledPin, OUTPUT);
}

void loop() {
  for (int i = 0; i < 3; i++) {
    pulse(pulseLength(i));
  }
  int n = 0;
  while (n < extra) {
    pulse(shortMs);
    n++;
  }
  if (extra >= 3) {
    extra = 0;
  } else {
    extra = extra + 1;
  }
  delay(1000);
}
