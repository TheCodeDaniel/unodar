import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): an async main that
// waits with Future.delayed. One diagnostic, saying why and what to write instead.
final led = Led(pin: LED_BUILTIN);

Future<void> main() async {
  while (true) {
    led.toggle();
    await Future.delayed(Duration(milliseconds: 500));
  }
}
