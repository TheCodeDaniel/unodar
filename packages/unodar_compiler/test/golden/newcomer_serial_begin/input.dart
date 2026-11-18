import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): opening Serial
// as in an Arduino sketch. One diagnostic, saying where the baud rate goes instead.
void main() => runDevice(Device(board: Uno(), children: [
      OnStart(() {
        Serial.begin(115200);
      }),
      Every(Duration(seconds: 1), () {
        Serial.println('tick');
      }),
    ]));
