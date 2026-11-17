import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): a button on
// pin 13, which the board LED already uses. One diagnostic, naming the widget that has the pin.
final led = Led(pin: LED_BUILTIN);
final button = Button(
    pin: 13,
    onPressed: () {
      led.toggle();
    });

void main() => runDevice(Device(board: Uno(), children: [led, button]));
