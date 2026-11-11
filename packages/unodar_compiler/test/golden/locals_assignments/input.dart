/// Local variables (typed, var, final, const, uninitialized, multiple) and assignment statements.
import 'package:unodar/unodar.dart';

int total = 0;

void setup() {}

void loop() {
  int n = 5;
  var m = n * 2;
  final k = m - 1;
  const step = 3;
  int later;
  later = k + step;
  int x = 1, y = 2;
  n = x + y;
  n += step;
  n -= 1;
  n++;
  n--;
  ++n;
  --n;
  total += n;
  total -= later;
  double level = 0.25;
  level += 1;
  level++;
  {
    int scoped = n;
    total = total + scoped;
  }
  delay(total > 0 ? total : 0);
}
