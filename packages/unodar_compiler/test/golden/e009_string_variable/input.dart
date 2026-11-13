import 'package:unodar/unodar.dart';

void report(String label) {
  Serial.println(label);
}

void setup() {
  Serial.begin(9600);
}

void loop() {
  Serial.println(1 > 0 ? 1 : 2.5);
}
