import 'package:unodar/unodar.dart';

// Classes I (Phase 6 step 3): a class with final and mutable fields of several types, one constructor with an
// initializing formal, a named parameter with a default, a required named parameter and an initializer list; two
// objects of it, used only through their fields. Also an avr8js behaviour program: each press on D2 changes `left`
// only, each tick of the Every changes `right` and prints both, so the two objects keep independent state.
const int start = 10;

class Counter {
  final int id;
  final int step;
  final Uint8 limit;
  int count = start;
  bool wrapped = false;
  double ratio;

  Counter(this.id, {this.step = 1, required int scale})
      : limit = Uint8(scale * 100),
        ratio = scale / 4;
}

final left = Counter(1, scale: 2);
final right = Counter(2, step: 5, scale: 3);

final press = Button(
    pin: 2,
    onPressed: () {
      left.count += left.step * 100;
      if (left.count > left.limit) {
        left.count = 0;
        left.wrapped = true;
      }
      left.ratio = left.ratio * 2;
    });

final tick = Every(Duration(milliseconds: 500), () {
  right.count += right.step;
  Serial.print(left.id);
  Serial.print(' ');
  Serial.print(left.count);
  Serial.print(' ');
  Serial.print(left.wrapped);
  Serial.print(' ');
  Serial.print(left.ratio);
  Serial.print(' | ');
  Serial.print(right.id);
  Serial.print(' ');
  Serial.print(right.count);
  Serial.print(' ');
  Serial.print(right.limit);
  Serial.print(' ');
  Serial.println(right.ratio);
});

void main() => runDevice(Device(board: Uno(), children: [press, tick]));
