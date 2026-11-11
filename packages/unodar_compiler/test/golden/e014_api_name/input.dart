/// A user declaration with the name of a unodar API function or constant shadows it in Dart but would clash in C++.
import 'package:unodar/unodar.dart';

int pinMode = 0;

void delay(int ms) {}

void setup() {
  int HIGH = 1;
}

void loop() {}
