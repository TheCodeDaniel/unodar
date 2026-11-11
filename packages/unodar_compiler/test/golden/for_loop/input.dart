import 'package:unodar/unodar.dart';

int sum = 0;

void setup() {}

void loop() {
  for (int i = 0; i < 3; i++) {
    sum += i;
  }
  for (var i = 10; i > 0; i -= 2) {
    if (i == 4) continue;
    if (i == 2) break;
    sum -= i;
  }
  int j;
  for (j = 0; j < 2; j = j + 1, sum++) {}
  for (;;) {
    break;
  }
  for (final double x = 0.5; sum < x;) {
    sum = 1;
  }
  delay(sum > 0 ? sum : 0);
}
