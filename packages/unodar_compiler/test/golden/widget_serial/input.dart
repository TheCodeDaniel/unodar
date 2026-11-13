import 'package:unodar/unodar.dart';

// A widget program that uses Serial: the generated setup() opens the port first, at Device's default 9600 baud.
final led = Led(pin: 13);

void report() {
  Serial.println('ready');
}

void main() => runDevice(Device(board: Uno(), children: [led]));
