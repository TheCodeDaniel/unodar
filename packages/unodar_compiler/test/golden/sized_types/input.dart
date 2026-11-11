import 'package:unodar/unodar.dart';

Uint8 level = Uint8(0);
Uint16 counter = Uint16(0);
Int16 delta = Int16(-5);

Uint8 brighter(Uint8 value) => Uint8(value + 16);

void setup() {}

void loop() {
  level = brighter(level);
  counter = Uint16(counter + 1);
  delta = Int16(-delta);
  final int sum = level + counter + delta;
  final bool wrapped = counter < level;
  final int product = level * level;
  if (wrapped || sum < 0 || product > 60000) {
    counter = Uint16(0);
  }
  delay(level);
}
