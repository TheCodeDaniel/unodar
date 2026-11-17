import 'package:unodar/unodar.dart';

class Counter {
  int count = 0;
}

class Holder {
  Counter loose = Counter();
  final Counter given;
  final Counter shared = first;

  Holder(this.given);

  void show() {
    Serial.println(loose);
  }
}

final first = Counter();

void setup() {}

void loop() {}
