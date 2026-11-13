import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void pause() {
  delay(50);
}

void blink() {
  led.on();
  pause();
  led.off();
}

// Not called from a callback: delay() is fine here (it is never reached).
void unused() {
  delay(10);
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Button(pin: 2, onPressed: () => blink()),
          Button(
              pin: 3,
              onPressed: () {
                pause();
              }),
        ],
      ),
    );
