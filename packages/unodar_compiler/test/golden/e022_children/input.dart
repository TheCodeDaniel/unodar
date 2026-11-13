import 'package:unodar/unodar.dart';

// Every top-level widget is listed in children exactly once.
final led = Led(pin: 13);
final forgotten = Led(pin: 12);

void main() => runDevice(Device(board: Uno(), children: [led, led]));
