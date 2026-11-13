import 'package:unodar/unodar.dart';

// A widget program with only LEDs: the generated setup() starts them, and loop() has nothing to poll.
const int ledPin = 13;
final led = Led(pin: ledPin);

void blinkOnce() {
  led.on();
  led.toggle();
  led.off();
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Led(pin: A0),
          Led(pin: 2 + 3),
        ],
      ),
    );
