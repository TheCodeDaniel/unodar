import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

final boot = OnStart(() {
  led.on();
});

void main() => runDevice(Device(board: Uno(), children: [led]));
