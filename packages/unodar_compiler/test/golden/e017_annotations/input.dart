@CppInclude('avr/wdt.h')
@CppInclude('../secret.h')
library;

import 'package:unodar/unodar.dart';

@CppHeader('Wire.h')
@CppClass('Two Wire')
abstract final class Bus {
  @CppName('write-byte')
  external void writeByte(@CppName('v') int value);
}

@CppClass('Ser' + 'vo')
@CppHeader('<Servo.h>')
abstract final class Motor {}

@CppName('helper')
@CppType('int')
void helper() {}

@CppInclude('Foo.h')
@CppHeader('Foo.h')
int count = 0;

void setup() {}

void loop() {}
