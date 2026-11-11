import 'package:unodar/unodar.dart';

int total = 0;

int bump() {
  total = 5;
  return 1;
}

void setup() {}

void loop() {
  total += bump();
  total -= bump();
  total = bump();
  int local = 0;
  local += bump();
}
