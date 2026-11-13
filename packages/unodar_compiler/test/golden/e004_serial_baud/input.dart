import 'package:unodar/unodar.dart';

void report() {
  Serial.println('ready');
}

void main() => runDevice(Device(board: Uno(), serialBaud: -9600, children: []));
