import 'package:unodar/unodar.dart';

const int zero = 0;
int a = 10 ~/ zero;
int b = 10 % zero;
double c = 1 / zero;

void setup() {}

void loop() {
  delay(5 ~/ 0);
  final d = 1.5 / 0;
}
