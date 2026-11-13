import 'package:unodar/unodar.dart';

// A widget's constant arguments are emitted in its C++ declaration, so they must be declared above it.
final led = Led(pin: ledPin);
const int ledPin = 13;

void main() => runDevice(Device(board: Uno(), children: [led]));
