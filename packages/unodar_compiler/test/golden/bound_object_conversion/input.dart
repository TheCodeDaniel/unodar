import 'package:unodar/unodar.dart';

// A constructor argument that is a conversion of a constant name. Emitted as `unodar::Led led(uint8_t(ledPin));`,
// C++ would read it as the declaration of a function `led` taking a uint8_t (the "most vexing parse"), so the
// conversion is parenthesized. Bound objects (`@CppClass`) take the same path.
const int ledPin = 13;
final led = Led(pin: Uint8(ledPin));

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Every(Duration(milliseconds: 500), () {
            led.toggle();
          }),
        ],
      ),
    );
