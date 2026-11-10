// Blink: toggles the Uno's built-in LED (pin 13) every half second.
//
// Build:   dart run packages/unodar_compiler/bin/unodar.dart build examples/blink/main.dart -o out
// Compile: arduino-cli compile --fqbn arduino:avr:uno out/main
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(13, HIGH);
  delay(500);
  digitalWrite(13, LOW);
  delay(500);
}
