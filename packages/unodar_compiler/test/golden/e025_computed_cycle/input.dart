import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final isOdd = Computed(() => count.value % 2 == 1);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(isOdd, (v) {
            count.value++;
          }),
        ],
      ),
    );
