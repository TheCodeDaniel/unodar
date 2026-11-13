import 'package:unodar/unodar.dart';

@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppType('uint8_t') int rx, @CppType('uint8_t') int tx);
  external void begin(@CppType('long') int baud);
  @CppName('write')
  @CppType('size_t')
  external int writeByte(@CppType('uint8_t') int value);
  @CppName('print')
  @CppType('size_t')
  external int printDouble(double value, {@CppType('int') int digits = 2});
}

final link = SoftSerial(300, -1);

void setup() {
  link.begin(9600);
}

void loop() {
  link.writeByte(256);
  link.printDouble(1.5, digits: 40000);
}
