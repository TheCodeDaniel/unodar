import 'package:unodar/unodar.dart';

@CppClass('Adafruit_BMP280')
final class Bmp280 {
  external Bmp280([int address = 0x76]);
  external double readTemperature([int retries = 1]);
  external String name();
  external void setLabel(String label, int? id);
  external void setMode(@CppType('int64_t') int mode);
  external void setScale(@CppType('float') int scale, @CppType('uint8_t') double gain);
  @CppType('bool')
  external int status();
  external T convert<T>(int value);
}

void setup() {}

void loop() {}
