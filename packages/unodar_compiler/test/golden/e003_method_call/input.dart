import 'package:unodar/unodar.dart';

int n = -5;

void setup() {}

void loop() {
  n = n.abs();
  print(n);
  delay(n.abs());
}
