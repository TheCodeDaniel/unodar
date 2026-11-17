import 'package:unodar/unodar.dart';

int level = 5;

class Gauge {
  int now = millis();
  final int base;
  final int offset;
  final int top;

  Gauge(this.base)
      : offset = level,
        top = later * 2;
}

const int later = 3;

final early = Probe(1);

class Probe {
  final int pin;
  Probe(this.pin);
}

final gauge = Gauge(level);

void setup() {}

void loop() {
  gauge.now = millis();
}
