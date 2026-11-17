import 'package:unodar/software_serial.dart';
import 'package:unodar/unodar.dart';

final gps = SoftwareSerial(10, 20);
final bad = SoftwareSerial(10, 3);

void setup() {
  gps.begin(250000);
  gps.begin(110);
  gps.write(256);
}

void loop() {}
