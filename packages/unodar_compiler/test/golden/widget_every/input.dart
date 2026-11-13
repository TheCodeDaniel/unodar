import 'package:unodar/unodar.dart';

// Every ticks one interval after setup(), then every interval; the interval is a constant Duration in ms.
const int blinkMs = 250;
int ticks = 0;
final led = Led(pin: LED_BUILTIN);
final heartbeat = Every(Duration(seconds: 1, milliseconds: blinkMs), () => led.toggle());

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          heartbeat,
          Every(const Duration(milliseconds: 500), () {
            ticks += 1;
            Serial.println('tick');
          }),
          Every(Duration(days: 24, hours: 20, minutes: 31, seconds: 23, milliseconds: 647), () {
            Serial.println(ticks);
          }),
        ],
      ),
    );
