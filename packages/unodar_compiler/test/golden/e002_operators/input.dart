import 'package:unodar/unodar.dart';

int a = 6;
int r = 0;
bool f = false;

void setup() {}

void loop() {
  r = a & 3;
  r = a | 1;
  r = a ^ 2;
  r = ~a;
  r = a << 2;
  r = a >> 1;
  r = a >>> 1;
  f = a is int;
  r = a as int;
  r = a ?? 1;
  r *= 2;
  r ~/= 2;
  r %= 2;
  r |= 1;
}
