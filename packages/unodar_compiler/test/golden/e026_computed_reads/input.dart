import 'package:unodar/unodar.dart';

int offset = 5;
final count = Signal<int>(0);
final total = Computed(() => count.value + offset);
final twice = Computed(() => later.value * 2);
final later = Signal<int>(0);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Every(Duration(seconds: 1), () {
            Serial.println(total.value + twice.value);
          }),
        ],
      ),
    );
