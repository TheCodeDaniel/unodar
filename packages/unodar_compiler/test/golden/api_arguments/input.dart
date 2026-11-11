/// Any int expression can be an argument to the unodar API; constant ones are range-checked.
import 'package:unodar/unodar.dart';

const int firstPin = 2;
int pin = 3;
int on = 1;

void setup() {
  pinMode(firstPin + 1, OUTPUT);
  pinMode(pin, on == 1 ? OUTPUT : INPUT);
}

void loop() {
  digitalWrite(pin, on == 1 ? HIGH : LOW);
  delay(60 * 1000);
  delay(pin * 100 + 5);
  digitalWrite(13, HIGH + LOW);
}
