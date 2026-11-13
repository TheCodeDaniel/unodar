import 'package:unodar/unodar.dart';

// Each pin belongs to one widget; A0 is pin 14.
final led = Led(pin: 14);
final button = Button(pin: A0, onPressed: () {});

void main() => runDevice(Device(board: Uno(), children: [led, button, Led(pin: 2), Button(pin: 2, onPressed: () {})]));
