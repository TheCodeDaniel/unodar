import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(-13, HIGH);
  delay(250 + 250);
}
