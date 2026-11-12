import 'package:unodar/unodar.dart';

const int precision = 4;

void setup() {
  Serial.begin(115200);
}

void loop() {
  final volts = analogRead(A0) * 5.0 / 1023;
  int places = 1;
  if (volts > 2.5) {
    places = 3;
  }
  Serial.println(volts);
  Serial.println(volts, digits: 3);
  Serial.print(volts, digits: 0);
  Serial.println(volts * 2, digits: precision);
  Serial.println(volts, digits: places);
  Serial.println(1.0 / 3, digits: precision + 2);
  delay(500);
}
