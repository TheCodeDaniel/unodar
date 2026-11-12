import 'package:unodar/unodar.dart';

// Runtime fidelity fixture (docs/PLAN.md step 8): compiled by unodar, run in avr8js by runtime_fidelity_test.dart.
// The inputs come from the simulated ADC and timers, so neither unodar nor avr-gcc can fold them; every check is
// an identity that holds in Dart for any input, so it must print PASS whatever voltages the runner sets.

void report(bool ok) {
  if (ok) {
    Serial.print('PASS ');
  } else {
    Serial.print('FAIL ');
  }
}

void setup() {
  Serial.begin(115200);
  final level = analogRead(A0); // 0..1023, a 16-bit C++ int
  final scaled = analogRead(A0) * 100; // the call result itself takes part in the multiplication
  final offset = analogRead(A1) - 1000; // -1000..23, often negative
  final start = micros();
  delay(3);
  final elapsed = micros() - start;

  report(scaled ~/ 100 == level);
  Serial.println('analogRead(A0) * 100 is computed in 32 bits');
  report(level * 64 == level * 32 + level * 32);
  Serial.println('analogRead(A0) * 64 keeps every bit');
  report(offset % 7 >= 0 && offset % 7 < 7);
  Serial.println('% is never negative');
  report((offset - offset % 7) % 7 == 0);
  Serial.println('x - x % 7 is a multiple of 7');
  report(offset ~/ 7 == -(-offset ~/ 7));
  Serial.println('~/ truncates toward zero');
  report(offset / 8 * 8 == offset);
  Serial.println('/ divides as double');
  report(Uint8(level) == level % 256);
  Serial.println('Uint8() wraps like % 256');
  report(Int16(offset * 30) == offset * 30);
  Serial.println('Int16() keeps values that fit');
  report(elapsed >= 3000 && elapsed < 4000);
  Serial.println('micros() advances by about 3000 across delay(3)');
  report(millis() >= 3);
  Serial.println('millis() advances');
  Serial.println('DONE');
}

void loop() {}
