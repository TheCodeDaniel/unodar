import 'package:unodar/unodar.dart';

final servo = Servo();

Servo pick() => servo;

void center(Servo s) {
  s.write(90);
}

void setup() {
  final local = Servo();
  Servo second = servo;
  center(servo);
  if (servo == servo) {
    servo.write(10);
  }
  Serial.begin(9600);
  final port = Serial;
  Wire.begin();
}

void loop() {}
