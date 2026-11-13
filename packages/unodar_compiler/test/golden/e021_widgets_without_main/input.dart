import 'package:unodar/unodar.dart';

// Widgets, Device, Uno and runDevice belong to a widget program (main()), not to a setup()/loop() sketch.
final led = Led(pin: 13);

void setup() {
  runDevice(Device(board: Uno(), children: [led]));
}

void loop() {
  led.toggle();
}
