import 'package:unodar/unodar.dart';

const int pin = 13;

void show(int value) {}

void setup() {
  final label = 'count';
  Serial.begin(9600);
}

void loop() {
  show('x' == 'y' ? 1 : 0);
  Serial.println(pin == 13 ? 'yes' : 'no');
}
