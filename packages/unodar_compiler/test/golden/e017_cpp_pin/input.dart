import 'package:unodar/unodar.dart';

@CppClass('Motor')
final class Motor {
  external Motor(@CppPin() double speed, @CppPin() @CppRange(2, 25) int pin);
  external void attach(@CppPin() int pin);
}

@CppPin()
int unused = 0;

void setup() {}

void loop() {}

class Plain {
  @CppName('read')
  int value() => 0;
}
