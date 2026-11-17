import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): a blink with
// delay() in a button callback. One diagnostic, saying why and what to use instead.
final led = Led(pin: LED_BUILTIN);

void main() => runDevice(Device(board: Uno(), children: [
      led,
      Button(
          pin: 2,
          onPressed: () {
            led.on();
            delay(1000);
            led.off();
          }),
    ]));
