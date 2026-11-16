import 'package:unodar/unodar.dart';

class Counter {
  int count = 0;
}

var shared = Counter();
final first = Counter();
final Counter alias = first;

int countOf(Counter c) => c.count;

Counter make() => first;

void setup() {
  final local = Counter();
  Serial.begin(9600);
  Serial.println(first);
  if (first == alias) {
    first.count++;
  }
}

void loop() {}
