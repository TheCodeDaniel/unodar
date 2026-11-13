import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

// delay() would stop every button and timer while it waits.
void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Every(Duration(seconds: 1), () {
            led.on();
            delay(100);
            led.off();
          }),
        ],
      ),
    );
