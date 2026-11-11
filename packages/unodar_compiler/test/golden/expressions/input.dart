/// Arithmetic, comparison, logical, ternary, unary, and precedence on runtime values.
import 'package:unodar/unodar.dart';

int a = 7;
int b = -2;
int c = 3;
bool p = true;
bool q = false;
double d = 1.5;
double e = 0;
int r = 0;
bool flag = false;

void setup() {}

void loop() {
  r = a + b * c;
  r = (a + b) * c;
  r = a - (b - c);
  r = a - b - c;
  r = -(a + b);
  r = -(-a);
  r = a - -b;
  r = a ~/ b;
  r = a % b;
  r = -a % c;
  r = a ~/ (b ~/ c);
  e = a / b;
  e = d / a;
  e = d * (d + a);
  e = -d;
  r = 60 * 1000;
  r = a * 1000;
  flag = a < b == p;
  flag = !(p && q);
  flag = p || q && flag;
  flag = (p || q) && flag;
  flag = a >= b && c != a;
  flag = d <= a;
  r = p
      ? a
      : q
          ? b
          : c;
  r = (p ? a : b) + c;
  r = p || q ? 1 : 2;
  delay(r > 0 ? r : 0);
}
