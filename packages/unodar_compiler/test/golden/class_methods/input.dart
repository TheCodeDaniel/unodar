import 'package:unodar/unodar.dart';

// Classes II (Phase 6 step 4): methods and getters. A method calls another method of the same object (implicitly)
// and a top-level function, reads and writes fields with and without `this.`; a getter has a block body; callbacks
// call methods and read a getter. Also an avr8js behaviour program: a press on D2 adds to `small` only, each tick
// adds to `large` and reports both, so a method only ever changes the object it is called on.
class Meter {
  final int step;
  int count = 0;
  int total = 0;

  Meter(this.step);

  void add(int times) {
    for (int i = 0; i < times; i++) {
      bump();
    }
    this.total += count;
  }

  void bump() => count += step;

  bool get big {
    final limit = limitFor(step);
    return count >= limit;
  }

  void report() {
    Serial.print(count);
    Serial.print(' ');
    Serial.print(this.total);
    Serial.print(' ');
    Serial.println(big);
  }
}

int limitFor(int step) => step * 2;

final small = Meter(1);
final large = Meter(7);

void main() => runDevice(Device(board: Uno(), children: [
      Button(
          pin: 2,
          onPressed: () {
            small.add(3);
          }),
      Every(Duration(milliseconds: 500), () {
        large.add(1);
        small.report();
        large.report();
        if (large.big) {
          Serial.println('large is big');
        }
      }),
    ]));
