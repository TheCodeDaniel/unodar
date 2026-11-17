import 'package:unodar/software_serial.dart';
import 'package:unodar/unodar.dart';

// Pins 0 and 1 are Serial's (the hardware port, wired to the USB chip), so a SoftwareSerial cannot use them, even in
// a program that never uses Serial. Pins 2 to 19 are fine; 20 is not a pin.
final onSerialRx = SoftwareSerial(0, 3);
final onSerialTx = SoftwareSerial(4, 1);
final beyond = SoftwareSerial(20, 5);
final fine = SoftwareSerial(2, 19);

void setup() {
  fine.begin(9600);
}

void loop() {}
