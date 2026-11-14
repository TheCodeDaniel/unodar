import 'package:unodar/unodar.dart';

// A chain of Watches without a cycle (plan step 7): the Watch of `a` writes `b`, the Watch of `b` writes `c`,
// through a function. Also an avr8js behaviour program: after each press, a, b and c are each delivered once, in
// that order, one pass apart; the program is then quiet.
final a = Signal<int>(0);
final b = Signal<int>(0);
final c = Signal<int>(0);

void copyToC(int v) {
  c.value = v * 10;
}

final press = Button(
    pin: 2,
    onPressed: () {
      a.value++;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          press,
          Watch(a, (v) {
            Serial.print('a ');
            Serial.println(v);
            b.value = v + 100;
          }),
          Watch(b, (v) {
            Serial.print('b ');
            Serial.println(v);
            copyToC(v);
          }),
          Watch(c, (v) {
            Serial.print('c ');
            Serial.println(v);
          }),
        ],
      ),
    );
