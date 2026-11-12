import 'package:unodar/unodar.dart';

int count = 0;

int bump() {
  count += 1;
  return count;
}

void setup() {}

void loop() {
  final jitter = micros() - micros();
  final both = digitalRead(2) + digitalRead(3);
  analogWrite(digitalRead(4), analogRead(A0));
  final mixed = bump() + analogRead(A1);
  count += bump() + count;
  // Fine: a nested call runs before the call that uses it, and API calls cannot change `count`.
  analogWrite(9, analogRead(A2) ~/ 4);
  final level = analogRead(A3) + count;
  count += millis();
  delay(jitter + both + mixed + level);
}
