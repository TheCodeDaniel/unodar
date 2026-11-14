import 'package:unodar/unodar.dart';

// Delivery order (plan step 6): flags and values are taken first, for every signal in declaration order; then the
// Watches of each changed signal run, signals in declaration order, Watches in `children` order. The Watch of `a`
// writes `b`, which is declared between `a` and `d`: that write is delivered in the next pass, after `d`. Without
// the snapshot it would be delivered in the same pass, before `d` (the negative control in runtime_fidelity_test).
final a = Signal<int>(0);
final b = Signal<int>(0);
final d = Signal<int>(0);
final press = Button(
    pin: 2,
    onPressed: () {
      a.value = 1;
      d.value = 1;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          press,
          Watch(d, (v) {
            Serial.print('d ');
            Serial.println(v);
          }),
          Watch(b, (v) {
            Serial.print('b ');
            Serial.println(v);
          }),
          Watch(a, (v) {
            Serial.print('a2 ');
            Serial.println(v);
          }),
          Watch(a, (v) {
            Serial.print('a ');
            Serial.println(v);
            b.value = v + 10;
          }),
        ],
      ),
    );
