import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): a StatelessWidget
// with a build(). One diagnostic: the Flutter names inside the class (BuildContext) are not reported separately.
class Blinker extends StatelessWidget {
  Widget build(BuildContext context) => Led(pin: LED_BUILTIN);
}

void main() => runDevice(Device(board: Uno(), children: [Led(pin: 13)]));
