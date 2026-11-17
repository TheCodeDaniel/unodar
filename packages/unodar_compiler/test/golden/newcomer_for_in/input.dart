import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): looping over a list
// of pins. One diagnostic, saying what to write instead.
void setup() {
  for (final pin in [2, 3, 4]) {
    pinMode(pin, OUTPUT);
  }
}

void loop() {}
