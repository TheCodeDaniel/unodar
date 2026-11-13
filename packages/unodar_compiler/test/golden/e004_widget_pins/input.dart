import 'package:unodar/unodar.dart';

// Widget pins are 0 to 19 on the Uno (D0-D13, A0-A5).
final led = Led(pin: 20);

void main() => runDevice(Device(board: Uno(), children: [led, Led(pin: -1)]));
