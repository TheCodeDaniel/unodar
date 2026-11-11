import 'package:unodar/unodar.dart';

int count = 0;

int next() {
  count += 1;
  return count;
}

void setup() {}

void loop() {
  delay(count + next());
}
