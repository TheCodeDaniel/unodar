import 'package:unodar/unodar.dart';

// Led(on: …) (plan step 9): the LED on pin 13 follows `lit`, which starts true, so it is lit at the end of setup();
// the LED on pin 12, written in children, follows `armed`. Observers of one signal (a bound Led, a Watch) run in
// children order. Also an avr8js behaviour program: each press on D2 flips `lit` and sets `armed`.
final lit = Signal(true);
final armed = Signal(false);
final status = Led(pin: 13, on: lit);
final button = Button(
    pin: 2,
    onPressed: () {
      lit.value = !lit.value;
      armed.value = true;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          status,
          button,
          Led(pin: 12, on: armed),
          Watch(lit, (v) {
            Serial.println(v);
          }),
        ],
      ),
    );
