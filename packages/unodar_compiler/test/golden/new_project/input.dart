import 'package:unodar/unodar.dart';

// The LED on the board (pin 13, marked L) blinks: on for half a second, off for half a second. Nothing to wire.
// Plug the Uno in and run `unodar flash`. Then try a button: see the README of this project.
final led = Led(pin: LED_BUILTIN);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Every(Duration(milliseconds: 500), () {
            led.toggle();
          }),
        ],
      ),
    );
