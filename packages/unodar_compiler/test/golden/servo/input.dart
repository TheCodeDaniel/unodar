import 'package:unodar/unodar.dart';

// Sweeps one servo with the pot on A0 and parks a second one.
final pan = Servo();
final tilt = Servo();
int lastAngle = -1;

void setup() {
  pan.attach(9); // min and max take their declared defaults, 544 and 2400 µs.
  tilt.attach(10, min: 600, max: 2300);
  tilt.writeMicroseconds(1500);
}

void loop() {
  final angle = analogRead(A0) * 180 ~/ 1023;
  if (angle != lastAngle) {
    pan.write(angle);
    lastAngle = angle;
  }
  if (pan.attached() && pan.read() > 170) {
    tilt.write(tilt.read() - 1);
  }
  if (tilt.readMicroseconds() < 700) {
    tilt.detach();
  }
  delay(15);
}
