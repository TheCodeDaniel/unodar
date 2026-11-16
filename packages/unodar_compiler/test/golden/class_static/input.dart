import 'package:unodar/unodar.dart';

// Static members (Phase 6 step 5): a `static const`, a `static final` and two static mutable fields, read and
// written with and without the class name, a static method, and a top-level constant computed from a static
// constant. Also an avr8js behaviour program: a press on D2 hits `a`, each tick hits `b` and reports; `created`
// counts the hits of both objects, because a static field is one variable for the whole class.
class Tally {
  static const int limit = 3;
  static final double rate = 0.5;
  static int created = 0;
  static int resets = 0;

  final int id;
  int count = 0;

  Tally(this.id);

  void hit() {
    count++;
    created++;
    if (count >= limit) {
      count = 0;
      Tally.resets++;
    }
  }

  void show() {
    Serial.print(created);
    Serial.print(' ');
    Serial.println(count);
  }

  static void report() {
    Serial.print(Tally.resets);
    Serial.print(' ');
    Serial.print(rate * limit);
    Serial.print(' ');
    Serial.println(twiceLimit);
  }
}

const int twiceLimit = Tally.limit * 2;

final a = Tally(1);
final b = Tally(2);

void main() => runDevice(Device(board: Uno(), children: [
      Button(
          pin: 2,
          onPressed: () {
            a.hit();
          }),
      Every(Duration(milliseconds: 500), () {
        b.hit();
        b.show();
        Tally.report();
      }),
    ]));
