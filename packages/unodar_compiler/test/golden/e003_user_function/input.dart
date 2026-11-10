import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void blink() {
  digitalWrite(13, HIGH);
}

void loop() {
  blink();
}
