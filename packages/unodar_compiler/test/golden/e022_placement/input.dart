import 'package:unodar/unodar.dart';

// A widget is a top-level `final`, or written directly inside Device(children: [...]).
var blinker = Led(pin: 3);
final led = Led(pin: 13);

void helper() {
  final local = Led(pin: 4);
  local.on();
}

void main() => runDevice(Device(board: Uno(), children: [led, blinker]));
