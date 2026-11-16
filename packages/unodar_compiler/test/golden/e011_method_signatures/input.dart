import 'package:unodar/unodar.dart';

class Motor {
  int speed = 0;

  void set(int value, {int ramp = 1}) {
    speed = value;
  }

  void nudge([int by = 1]) {
    speed += by;
  }

  T pick<T>(T a) => a;

  void go(value) {}
}

void setup() {}

void loop() {}
