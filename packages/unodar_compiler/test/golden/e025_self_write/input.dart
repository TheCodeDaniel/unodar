import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final level = Signal<int>(0);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(count, (v) {
            count.value = v + 1;
          }),
          Watch(level, (v) {
            if (v > 10) {
              level.value++;
            }
          }),
        ],
      ),
    );
