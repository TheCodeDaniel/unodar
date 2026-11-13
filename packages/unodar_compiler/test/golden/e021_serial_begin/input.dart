import 'package:unodar/unodar.dart';

int speed = 9600;

// A widget program never opens Serial itself; serialBaud: is a constant, and an unsigned long.
void report() {
  Serial.begin(9600);
  Serial.println('ready');
}

void main() => runDevice(Device(board: Uno(), serialBaud: speed, children: [Led(pin: 13)]));
