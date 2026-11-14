import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final other = Signal<int>(0);
final copy = count;

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Button(
              pin: 2,
              onPressed: () {
                Serial.println(count);
                if (count == other) {
                  count.value = 1;
                }
              }),
        ],
      ),
    );
