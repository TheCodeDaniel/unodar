import 'package:unodar/unodar.dart';

final lit = Signal(true);
final status = Led(pin: 13, on: lit);
final spare = Led(pin: 12);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          status,
          spare,
          Button(
              pin: 2,
              onPressed: () {
                status.toggle();
                status.set(false);
                spare.toggle();
              }),
        ],
      ),
    );
