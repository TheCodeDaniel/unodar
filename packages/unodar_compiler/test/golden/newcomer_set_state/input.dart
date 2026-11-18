import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): setState in a
// callback. One diagnostic: the closure passed to it is not reported separately.
int count = 0;

void main() => runDevice(Device(board: Uno(), children: [
      Button(
          pin: 2,
          onPressed: () {
            setState(() {
              count++;
            });
          }),
    ]));
