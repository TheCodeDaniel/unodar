import 'package:unodar/unodar.dart';

class Walker {
  int steps = 0;

  void walk(int n) {
    if (n > 0) walk(n - 1);
  }

  void left(int n) {
    if (n > 0) right(n - 1);
  }

  void right(int n) {
    if (n > 0) left(n - 1);
  }

  int get depth => deeper(steps);
}

int deeper(int n) => n > 10 ? n : walker.depth;

final walker = Walker();

void setup() {}

void loop() {
  walker.walk(3);
}
