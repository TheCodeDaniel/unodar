import 'package:unodar/unodar.dart';

void setup() {
  Serial.begin(-9600);
}

void loop() {
  final level = analogRead(A0);
  Serial.println(level, digits: 2);
  Serial.println(level > 3, digits: 1);
  Serial.println('volts', digits: 1);
  Serial.println(level / 1023, digits: 300);
  Serial.print(level / 1023, digits: -1);
}
