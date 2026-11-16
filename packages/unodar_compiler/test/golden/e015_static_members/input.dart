import 'package:unodar/unodar.dart';

int level = 2;

class Clock {
  static int started = millis();
  static final int base = level * 10;
  static const int step = Later.size;
}

const int early = Later.size + 1;

class Later {
  static const int size = 4;
}

void setup() {}

void loop() {
  Clock.started = millis();
}
