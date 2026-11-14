import 'package:unodar/unodar.dart';

// A Watch callback whose parameter is `_` (it ignores the value). Under the package's Dart 3.6 language version `_`
// is an ordinary name; from 3.7 it is a non-binding wildcard. Either way it becomes the C++ parameter `int32_t _`,
// which is valid (names starting with `_` are reserved only at global scope). Also an avr8js behaviour program:
// the delivery at the end of setup() toggles the LED on, each press on D2 toggles it again.
final count = Signal<int>(0);
final led = Led(pin: 13);
final button = Button(
    pin: 2,
    onPressed: () {
      count.value++;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          button,
          Watch(count, (_) {
            led.toggle();
          }),
        ],
      ),
    );
