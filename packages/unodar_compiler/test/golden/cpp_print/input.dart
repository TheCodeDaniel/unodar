import 'package:unodar/unodar.dart';

// @CppPrint (Phase 6 step 15): a user binding of a Print-derived C++ class gets Serial's print dispatch. A string
// literal is a flash string, a bool prints true/false, a double takes digits, an empty println is a line break. Also
// an avr8js behaviour program: the TX pin (11) is decoded from the pin log.
@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
@CppPrint()
final class SoftSerial {
  external SoftSerial(@CppPin() @CppType('uint8_t') int rx, @CppPin() @CppType('uint8_t') int tx);
  external void begin(@CppType('long') int baud);
  external void print(Object value, {int digits = 2});
  external void println(Object value, {int digits = 2});
}

final link = SoftSerial(10, 11);

void setup() {
  link.begin(9600);
  final ready = digitalRead(2) == LOW;
  link.print('ready ');
  link.println(ready);
  link.println(!ready);
  link.print(1.0 / 3, digits: 4);
  link.print(' ');
  link.println(-42);
  final small = Uint8(200);
  link.println(small);
  link.println('');
  link.println('DONE');
}

void loop() {}
