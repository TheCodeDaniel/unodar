import 'package:unodar/unodar.dart';

@CppClass('SoftwareSerial')
@CppHeader('SoftwareSerial.h')
@CppPrint()
abstract final class Port {
  external void print(Object value);
  @CppName('write')
  external int println(Object value, {int digits = 2});
}

@CppClass('Servo')
@CppHeader('Servo.h')
@CppPrint()
abstract final class NoPrint {
  external void attach(int pin);
}

@CppClass('Servo')
@CppHeader('Servo.h')
abstract final class Plain {
  external void print(Object value, {int digits = 2});
}

@CppPrint()
final class Mine {}

void setup() {}

void loop() {}
