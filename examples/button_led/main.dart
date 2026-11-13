// Button LED: the Phase 4 goal program. A push button on pin 2 toggles the LED on pin 13 (the Uno's built-in LED,
// marked L), and the serial monitor shows `tick` twice a second. Written as a static widget tree: no setup(), no
// loop(); the compiler generates them from main().
//
// Wiring: a push button between pin 2 and GND (the internal pull-up is used, no resistor).
// Build:   dart run packages/unodar_compiler/bin/unodar.dart build examples/button_led/main.dart -o out
//          (writes out/main/main.ino and out/main/unodar_widgets.h; arduino-cli compiles the folder)
import 'package:unodar/unodar.dart';

final led = Led(pin: 13);
final button = Button(
    pin: 2,
    onPressed: () {
      led.toggle();
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          button,
          Every(Duration(milliseconds: 500), () {
            Serial.println('tick');
          }),
        ],
      ),
    );
