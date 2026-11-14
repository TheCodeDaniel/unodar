import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
var loose = Computed(() => count.value + 1);
final Computed<num> wide = Computed(() => count.value);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Button(
              pin: 2,
              onPressed: () {
                final inner = Computed(() => count.value);
              }),
        ],
      ),
    );
