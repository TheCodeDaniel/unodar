import 'package:unodar/unodar.dart';

class byte {}

class Servo {}

class Limits {
  int min = 0;
  final int LOW_LIMIT = 1;
  int unodar_top;

  Limits(this.unodar_top, {int max = 5}) : min = max;
}

void setup() {}

void loop() {}
