import 'package:unodar/unodar.dart';

int count = 0;

int next() {
  count += 1;
  return count;
}

void show(int x, int y) {}

void setup() {}

void loop() {
  show(next(), next());
  show(count, next());
  show(1, next());
  final value = next();
  show(count, value);
}
