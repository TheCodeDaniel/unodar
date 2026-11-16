import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void flash() {
  led.on();
  delay(50);
  led.off();
}

void main() => runDevice(Device(board: Uno(), children: [
      led,
      OnStart(() {
        flash();
      }),
      Button(
          pin: 2,
          onPressed: () {
            flash();
          }),
    ]));
