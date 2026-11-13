import 'package:unodar/unodar.dart';

final servo = Servo();

void setup() {
  servo.attach(9, min: 40000);
  servo.attach(-32769, max: 2400);
}

void loop() {
  servo.write(32768);
  servo.writeMicroseconds(-40000);
}
