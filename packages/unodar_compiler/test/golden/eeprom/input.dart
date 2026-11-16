import 'package:unodar/eeprom.dart';
import 'package:unodar/unodar.dart';

// The EEPROM wrapper (Phase 6 step 13), imported on its own. Byte 0 counts boots (an erased EEPROM reads 255),
// byte 1 is updated twice to the same value, which writes it at most once. Also an avr8js behaviour program: run
// twice on the same EEPROM file, the second run sees the first run's count.
const int bootsAddress = 0;
const int flagAddress = 1;

void setup() {
  Serial.begin(9600);
  int boots = EEPROM.read(bootsAddress);
  if (boots == 255) boots = 0;
  Serial.print('boot ');
  Serial.println(boots);
  EEPROM.write(bootsAddress, boots + 1);
  EEPROM.update(flagAddress, 66);
  EEPROM.update(flagAddress, 66);
  Serial.print('size ');
  Serial.println(EEPROM.length());
  Serial.println('DONE');
}

void loop() {}
