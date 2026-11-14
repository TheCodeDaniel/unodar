import 'package:unodar/unodar.dart';

// Delivering a Computed (plan step 11): in unodar_deliver() a watched Computed is re-evaluated when a signal it
// reads changed, and delivered only if its value differs from the value it last delivered (+2 keeps `isOdd`). Every
// Computed is settled before any observer runs, so the Watch of `isOdd` sees `v == isOdd.value`, and observers keep
// declaration order (count, isOdd, other). The Led on pin 13 follows `isOdd`. Also an avr8js behaviour program.
final count = Signal<int>(0);
final isOdd = Computed(() => count.value % 2 == 1);
final other = Signal<int>(0);
final led = Led(pin: 13, on: isOdd);
final plusOne = Button(
    pin: 2,
    onPressed: () {
      count.value++;
      other.value++;
    });
final plusTwo = Button(
    pin: 3,
    onPressed: () {
      count.value += 2;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          plusOne,
          plusTwo,
          Watch(count, (v) {
            Serial.print('count ');
            Serial.println(v);
          }),
          Watch(isOdd, (v) {
            Serial.print('odd ');
            Serial.print(v);
            Serial.print(' ');
            Serial.println(isOdd.value);
          }),
          Watch(other, (v) {
            Serial.print('other ');
            Serial.println(v);
          }),
        ],
      ),
    );
