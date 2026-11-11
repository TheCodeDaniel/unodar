import 'package:unodar/unodar.dart';

int a() => 1;

int b() => 2;

void setup() {}

void loop() {
  delay(a() + b());
  delay(a() * (b() - 1));
  if (a() > 0 && b() > 0) {}
  delay(a() > 0 ? b() : 0);
}
