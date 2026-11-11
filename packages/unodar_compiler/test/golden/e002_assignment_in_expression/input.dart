import 'package:unodar/unodar.dart';

int a = 0;
int b = 0;

void setup() {}

void loop() {
  delay(a = 5);
  b = a++;
  b = --a;
  b = (a = 3) + 1;
  if ((a += 1) > 2) {}
}
