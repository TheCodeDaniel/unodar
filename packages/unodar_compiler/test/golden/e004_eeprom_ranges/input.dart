import 'package:unodar/eeprom.dart';
import 'package:unodar/unodar.dart';

void setup() {
  EEPROM.write(1024, 1);
  EEPROM.update(-1, 300);
  EEPROM.read(1023);
}

void loop() {}
