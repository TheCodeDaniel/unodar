import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          ...[Led(pin: 3)],
          if (true) Led(pin: 4),
          for (int i = 0; i < 1; i++) Led(pin: 5),
        ],
      ),
    );
