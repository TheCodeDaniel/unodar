import 'package:unodar/unodar.dart';

int period = 500;
const tooShort = 0;

// The interval is a Duration(…) written in place, with constant arguments adding up to whole milliseconds from 1
// to 2147483647.
void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Every(Duration(microseconds: 1500), () {}),
          Every(Duration(milliseconds: tooShort), () {}),
          Every(Duration(days: 25), () {}),
          Every(Duration(milliseconds: period), () {}),
          Every(Duration.zero, () {}),
        ],
      ),
    );
