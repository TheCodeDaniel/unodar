import 'package:unodar/unodar.dart';

int ledPin = 13;
final led = Led(pin: ledPin);
final pinFromCall = Led(pin: digitalRead(2));

void main() => runDevice(Device(board: Uno(), children: [led, pinFromCall, Led(pin: ledPin + 1)]));
