import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(count, ([int v = 0]) {}),
          Watch(count, (v) async {}),
          Watch(count, (v) {
            final f = () {};
          }),
        ],
      ),
    );
