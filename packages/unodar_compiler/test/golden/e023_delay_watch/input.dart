import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final led = Led(pin: 13);

void flash() {
  led.on();
  delay(50);
  led.off();
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Watch(count, (v) {
            flash();
          }),
        ],
      ),
    );
