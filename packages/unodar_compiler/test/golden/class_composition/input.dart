import 'package:unodar/unodar.dart';

// Composition (Phase 6 step 6): a class whose final fields hold objects created in place, one by its field
// initializer and one in the initializer list from a constructor parameter, plus a bound Servo member. Members are
// used through chains (`pair.small.add()`, `other.large.step`, `pair.arm.write(90)`) and from methods (`small`,
// `this.large`). Also an avr8js behaviour program: setup() prints what each object holds, so a member is the
// object itself, never a copy.
class Counter {
  final int step;
  int count = 0;

  Counter(this.step);

  void add() {
    count += step;
  }
}

class Pair {
  final Counter small = Counter(1);
  final Counter large;
  final Servo arm = Servo();
  int rounds = 0;

  Pair(int scale) : large = Counter(scale * 10);

  void advance() {
    small.add();
    this.large.add();
    rounds++;
  }

  int get total => small.count + large.count;
}

final pair = Pair(3);
final other = Pair(5);

void setup() {
  Serial.begin(9600);
  pair.arm.attach(9);
  pair.advance();
  pair.advance();
  other.advance();
  pair.small.add();
  Serial.println(pair.total);
  Serial.println(other.total);
  Serial.println(pair.rounds);
  Serial.println(other.large.step);
  pair.arm.write(90);
  Serial.println(pair.arm.read());
  Serial.println(other.arm.attached());
}

void loop() {}
