import 'package:unodar/unodar.dart';

// Servo 1.3.0 stores (544 - min) / 4 in an int8_t: only min 33..1059 works.
final servo = Servo();

void setup() {
  servo.attach(9, min: 33);
  servo.attach(9, min: 1059);
  servo.attach(9, min: 32);
  servo.attach(9, min: 1060);
  servo.attach(9, min: 0, max: 2400);
}

void loop() {}
