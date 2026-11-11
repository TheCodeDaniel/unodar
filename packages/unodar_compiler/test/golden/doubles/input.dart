import 'package:unodar/unodar.dart';

double voltage = 0;
const double scale = 5.0 / 1023;
int reading = 512;

double toVolts(int raw) => raw * scale;

void setup() {}

void loop() {
  voltage = toVolts(reading);
  final double half = voltage / 2;
  final double ratio = reading / 1023;
  final double mixed = half + reading - 0.5 * ratio;
  final bool high = voltage >= 2.5 && mixed != 0;
  if (high) {
    reading -= 1;
  } else {
    reading += 1;
  }
  voltage = -voltage;
  delay(10);
}
