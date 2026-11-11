import 'package:unodar/unodar.dart';

int count = 0;

void setup() {}

void loop() {
  do {
    count *= 2;
  } while (count < 100);
  delay(count++);
}
