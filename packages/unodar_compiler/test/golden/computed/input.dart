import 'package:unodar/unodar.dart';

// Computed reads (plan step 10): reading a Computed evaluates its expression, so it is never out of date, even right
// after a write in the same callback. Computeds read signals, Computeds above them, `const` and `final` values.
// Also an avr8js behaviour program: each press on D2 changes both signals and prints every Computed.
const int scale = 3;
final int offset = 1;
final count = Signal<int>(0);
final level = Signal(Uint8(200));
final isOdd = Computed(() => count.value % 2 == 1);
final scaled = Computed(() => count.value * scale + level.value - offset);
final half = Computed(() => count.value / 2);
final label = Computed(() => isOdd.value ? scaled.value : -scaled.value);

final press = Button(
    pin: 2,
    onPressed: () {
      count.value++;
      level.value = Uint8(level.value + 50);
      Serial.print(isOdd.value);
      Serial.print(' ');
      Serial.print(scaled.value);
      Serial.print(' ');
      Serial.print(half.value);
      Serial.print(' ');
      Serial.println(label.value);
    });

void main() => runDevice(Device(board: Uno(), children: [press]));
