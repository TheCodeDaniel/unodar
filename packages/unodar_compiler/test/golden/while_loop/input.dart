import 'package:unodar/unodar.dart';

int count = 0;

void setup() {}

void loop() {
  int n = 0;
  while (n < 3) {
    n++;
  }
  while (true) {
    count += 1;
    if (count > 10) {
      break;
    }
    if (count % 2 == 0) {
      continue;
    }
    delay(count);
  }
  while (count > 0) count--;
}
