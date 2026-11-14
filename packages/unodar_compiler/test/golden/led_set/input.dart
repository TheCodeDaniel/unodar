import 'package:unodar/unodar.dart';

// Led.set(bool) (plan step 8), in the maintainer's target example: the LED on pin 13 shows whether the count is
// odd. Also an avr8js behaviour program: the initial delivery switches the LED to `false` (it stays off), and each
// debounced press on D2 flips it.
final count = Signal<int>(0);
final led = Led(pin: 13);
final button = Button(
    pin: 2,
    onPressed: () {
      count.value = count.value + 1;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          button,
          Watch(count, (v) {
            led.set(v % 2 == 1);
            Serial.println(v);
          }),
        ],
      ),
    );
