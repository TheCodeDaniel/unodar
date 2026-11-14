import 'package:unodar/unodar.dart';

// `Led.set` is declared in package:unodar (Phase 5, plan step 3) but not supported by the compiler until plan step 8,
// so it is an unknown method (E003), not an internal error. Step 8 replaces this golden with the positive `led_set`.
final led = Led(pin: 13);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Every(Duration(seconds: 1), () {
            led.set(true);
          }),
        ],
      ),
    );
