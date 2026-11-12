import 'package:unodar/unodar.dart';

@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppType('uint8_t') int rx, @CppType('uint8_t') int tx);
  @CppType('int')
  external int read();
}

final link = SoftSerial(10, 11);
final servo = Servo();
int total = 0;

void setup() {}

void loop() {
  // Two side-effecting reads in one expression: C++ may evaluate them in either order.
  final reading = Wire.read() * 256 + Wire.read();
  final pair = link.read() - link.read();
  final mixed = Wire.read() + link.read();
  final angle = servo.read() + analogRead(A0);
  servo.write(Wire.read() + servo.read());
  total += Wire.read() + Wire.available();
  // Still fine: a method call next to a mutable global (methods cannot change `total`), and a nested call.
  final next = Wire.read() + total;
  servo.write(link.read());
  delay(reading + pair + mixed + angle + next);
}
