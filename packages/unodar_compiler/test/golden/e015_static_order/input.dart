import 'package:unodar/unodar.dart';

class Timing {
  static const int total = step * 4;
  static const int step = 25;
  static final int margin = Timing.limit - 1;
  static final int limit = 90;
  static int ticks = step;
  static const int base = 10;
  static const int top = base * 2;
  static const int doubled = Timing.base * 2;
}

void setup() {}

void loop() {
  Timing.ticks++;
}
