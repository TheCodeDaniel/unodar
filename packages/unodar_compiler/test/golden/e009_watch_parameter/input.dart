import 'package:unodar/unodar.dart';

final ratio = Signal(0.5);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(ratio, (num r) {
            Serial.println(r > 1);
          }),
        ],
      ),
    );
