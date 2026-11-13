import 'package:unodar/unodar.dart';

const int low = 1;

@CppClass('Dimmer')
abstract final class Dimmer {
  external void level(@CppType('uint8_t') @CppRange(0, 300) int value);
  external void gain(@CppRange(1, 2) double factor);
  external void scale(@CppRange(10, 5) int value);
  external void step(@CppRange(low, 9) int value);
  external void mode({@CppType('int') @CppRange(1, 3) int value = 0});
  external void fine(@CppType('int8_t') @CppRange(-128, 127) int value);
}

@CppRange(0, 1)
void helper() {}

void setup() {}

void loop() {}
