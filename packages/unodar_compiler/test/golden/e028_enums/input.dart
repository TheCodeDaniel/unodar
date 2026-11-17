import 'package:unodar/unodar.dart';

enum Mode { idle, heating }

enum Speed {
  slow(1),
  fast(2);

  const Speed(this.factor);
  final int factor;
}

enum Shape implements Comparable<Shape> {
  dot,
  box;

  @override
  int compareTo(Shape other) => index - other.index;
}

Mode mode = Mode.idle;

void setup() {}

void loop() {
  final all = Mode.values;
  Serial.println(mode.name);
}
