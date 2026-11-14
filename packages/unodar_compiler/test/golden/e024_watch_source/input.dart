import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
var total = Signal<int>(0);
final flag = true;

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(flag ? count : count, (v) {}),
          Watch(total, (v) {}),
          Watch(count, (v) {}),
        ],
      ),
    );
