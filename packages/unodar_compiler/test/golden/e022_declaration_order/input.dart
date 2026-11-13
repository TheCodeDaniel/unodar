import 'package:unodar/unodar.dart';

// A top-level widget's callback may only use widgets declared above it.
final button = Button(
    pin: 2,
    onPressed: () {
      led.toggle();
    });
final led = Led(pin: 13);

void main() => runDevice(Device(board: Uno(), children: [button, led, Button(pin: 3, onPressed: () => led.off())]));
