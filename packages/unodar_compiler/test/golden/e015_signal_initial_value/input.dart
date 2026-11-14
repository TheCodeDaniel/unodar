import 'package:unodar/unodar.dart';

int start = 3;
final level = Signal(analogRead(A0));
final count = Signal(start);
final limit = Signal(maximum);
const int maximum = 10;

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Every(Duration(seconds: 1), () {
            Serial.println(level.value + count.value + limit.value);
          }),
        ],
      ),
    );
