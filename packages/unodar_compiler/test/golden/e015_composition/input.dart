import 'package:unodar/unodar.dart';

int level = 3;

class Panel {
  final Gauge early = Gauge(1);
  final Knob knob = Knob(level);
  final Knob scaled;

  Panel(int scale) : scaled = Knob(scale * level);
}

class Gauge {
  final int pin;
  Gauge(this.pin);
}

class Knob {
  final int pin;
  Knob(this.pin);
}

void setup() {}

void loop() {}
