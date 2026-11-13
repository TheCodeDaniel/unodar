import 'package:unodar/unodar.dart';

const int pin = 13;

void setup() {
  cpp('pinMode($pin, OUTPUT);');
  cpp('digitalWrite(' '${pin + 0}' ', HIGH);');
}

void loop() {}
