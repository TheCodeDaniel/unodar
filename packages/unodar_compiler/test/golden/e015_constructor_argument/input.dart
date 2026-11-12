import 'package:unodar/unodar.dart';

@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppType('uint8_t') int rx, @CppType('uint8_t') int tx);
}

int rx = 10;
int pick() => 3;

final link = SoftSerial(rx, 11);
final other = SoftSerial(pick(), tx);
const int tx = 12;

void setup() {}

void loop() {}
