import 'package:unodar/unodar.dart';

int count = 0;

void setup() {}

void loop() {
  do {
    count += 1;
  } while (count < 100);
  count *= 2;
  delay(count++);
}
