import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(count, (abs) {
            Serial.println(abs);
          }),
        ],
      ),
    );
