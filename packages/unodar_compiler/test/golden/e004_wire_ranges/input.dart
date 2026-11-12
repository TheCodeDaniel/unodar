import 'package:unodar/unodar.dart';

void setup() {
  Wire.begin();
  Wire.setClock(-1);
}

void loop() {
  Wire.beginTransmission(0x100);
  Wire.write(-1);
  Wire.write(256);
  Wire.endTransmission();
  Wire.requestFrom(0x68, 40000);
  // Two reads in one expression: C++ may run them in either order (E013).
  final both = Wire.read() * 256 + Wire.read();
  delay(both);
}
