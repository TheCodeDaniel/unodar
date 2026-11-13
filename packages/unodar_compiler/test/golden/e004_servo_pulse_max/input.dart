import 'package:unodar/unodar.dart';

// Servo 1.3.0 stores (2400 - max) / 4 in an int8_t: only max 1889..2915 works.
final servo = Servo();

void setup() {
  servo.attach(9, max: 1889);
  servo.attach(9, max: 2915);
  servo.attach(9, max: 1888);
  servo.attach(9, max: 2916);
  servo.attach(9, min: 544, max: 3000);
}

void loop() {}
