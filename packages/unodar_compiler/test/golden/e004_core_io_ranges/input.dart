import 'package:unodar/unodar.dart';

void setup() {}

void loop() {
  final value = digitalRead(256);
  final level = analogRead(-1);
  analogWrite(3, 40000);
  analogWrite(300, value + level);
}
