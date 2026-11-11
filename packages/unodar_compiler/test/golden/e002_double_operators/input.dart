/// Operators Dart allows on doubles but C++ has no equivalent for.
import 'package:unodar/unodar.dart';

double d = 7.5;
int i = 2;
double r = 0;
int q = 0;

void setup() {}

void loop() {
  r = d % 2;
  r = i % 2.5;
  q = d ~/ 2;
  q = i ~/ 0.5;
  r = d.remainder(2);
}
