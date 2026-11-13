import 'package:unodar/unodar.dart';

// Buttons poll in loop(); each callback becomes a plain generated function.
int presses = 0;
final led = Led(pin: 13);
final button = Button(
  pin: 2,
  onPressed: () {
    presses += 1;
    led.toggle();
    report(presses);
  },
);

void report(int count) {
  Serial.print('presses=');
  Serial.println(count);
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          button,
          Button(pin: A1, onPressed: () => led.off()),
        ],
      ),
    );
