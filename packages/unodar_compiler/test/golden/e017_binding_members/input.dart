import 'package:unodar/unodar.dart';

@CppClass('Sensor')
final class Sensor {
  int address = 0x76;
  external Sensor();
  Sensor.named();
  int get level => 0;
  set level(int value) {}
  external static void resetAll();
  int operator +(int other) => other;
  void calibrate() {}
  external int read();
}

@CppClass('Base')
abstract final class Derived extends Object implements Comparable<int> {}

@CppClass('Thing')
final class Thing {}

void setup() {}

void loop() {}
