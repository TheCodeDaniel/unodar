import 'package:unodar/unodar.dart';

// serialBaud: sets the speed the generated setup() opens Serial at.
const int baud = 115200;

void report() {
  Serial.print(42);
}

void main() => runDevice(Device(board: Uno(), serialBaud: baud, children: [Led(pin: 13)]));
