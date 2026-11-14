// Counter: the Phase 5 goal program. A push button on pin 2 counts up, one on pin 3 clears the count, the Uno's
// built-in LED (pin 13, marked L) is lit while the count is odd, and the serial monitor shows every new count.
// State lives in a Signal; `isOdd` is a Computed of it; the LED follows `isOdd`, and a Watch prints the count.
// Clearing a count that is already 0 writes an equal value, which delivers nothing.
//
// Wiring: push buttons between pin 2 and GND and between pin 3 and GND (internal pull-ups, no resistors).
// Build:   dart run packages/unodar_compiler/bin/unodar.dart build examples/counter/main.dart -o out
//          (writes out/main/main.ino and out/main/unodar_widgets.h; arduino-cli compiles the folder)
import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final isOdd = Computed(() => count.value % 2 == 1);
final led = Led(pin: 13, on: isOdd);
final plus = Button(
    pin: 2,
    onPressed: () {
      count.value++;
    });
final clear = Button(
    pin: 3,
    onPressed: () {
      count.value = 0;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          plus,
          clear,
          Watch(count, (v) {
            Serial.println(v);
          }),
        ],
      ),
    );
