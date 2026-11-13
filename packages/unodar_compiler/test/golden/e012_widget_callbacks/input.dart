import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void toggle() {
  led.toggle();
}

// A callback is a closure `() { … }`: not a function reference, not async, no closures inside, no value.
void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Button(pin: 2, onPressed: toggle),
          Button(
              pin: 3,
              onPressed: () async {
                toggle();
              }),
          Button(
              pin: 4,
              onPressed: () {
                final inner = () => toggle();
              }),
          Button(pin: 5, onPressed: () => 42),
        ],
      ),
    );
