/// A serial port on any two pins, in software (Arduino's SoftwareSerial library, part of the AVR core), for GPS,
/// Bluetooth and other serial modules while `Serial` stays the USB console. Import it on its own:
/// `import 'package:unodar/software_serial.dart';`.
///
/// ```dart
/// final gps = SoftwareSerial(10, 11);   // RX on pin 10, TX on pin 11
/// gps.begin(9600);
/// gps.println('hello');
/// if (gps.available() > 0) Serial.println(gps.read());
/// ```
///
/// See docs/SUBSET.md "SoftwareSerial" for what it blocks, the costs and what is verified in the simulator.
library;

export 'src/software_serial.dart';
