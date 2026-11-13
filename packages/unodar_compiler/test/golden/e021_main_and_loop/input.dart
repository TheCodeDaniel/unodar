import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void main() => runDevice(Device(board: Uno(), children: [led]));

void setup() {
  led.on();
}

void loop() {}
