/// The EEPROM of the Uno: 1024 bytes that keep their values when the board is off (Arduino's EEPROM library, part
/// of the AVR core). Import it on its own: `import 'package:unodar/eeprom.dart';`.
///
/// ```dart
/// final saved = EEPROM.read(0);
/// EEPROM.update(0, setpoint);   // writes only if the byte differs
/// ```
///
/// See docs/SUBSET.md "EEPROM" for the costs and what is verified in the simulator.
library;

export 'src/eeprom.dart';
