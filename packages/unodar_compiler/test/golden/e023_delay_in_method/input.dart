import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

class Blinker {
  int times = 0;

  void blink() {
    led.on();
    pause();
    led.off();
    times++;
  }

  void pause() {
    delay(100);
  }
}

final blinker = Blinker();

void main() => runDevice(
      Device(board: Uno(), children: [
        led,
        Button(
            pin: 2,
            onPressed: () {
              blinker.blink();
            }),
      ]),
    );
