import 'package:unodar/unodar.dart';

const int pin = 300;

void setup() {
  pinMode(pin, OUTPUT);
  pinMode(13, 256);
}

void loop() {
  digitalWrite(13, -1);
  delay(-2147483647 - 1);
  delay(0);
  digitalWrite(255, 255);
}
