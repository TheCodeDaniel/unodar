import 'package:unodar/unodar.dart';

// Signals as state (plan step 5, no Watch yet): a Button writes them in every supported form, an Every reads them.
// Also the avr8js behaviour program of runtime_fidelity_test: a press on D2 changes every signal, the Every prints
// them once a second. Uint8(250 + 3 + 3) wraps to 0 and Int16(-30000 - 3000) to 32536, as in Dart; depth * 1000
// needs 32 bits.
final count = Signal<int>(0);
final ratio = Signal(0.5);
final lit = Signal(false);
final level = Signal(Uint8(250));
final depth = Signal(Int16(-30000));

final plus = Button(
    pin: 2,
    onPressed: () {
      count.value++;
      count.value += 10;
      count.value -= 5;
      count.value--;
      ratio.value = ratio.value * 2;
      lit.value = !lit.value;
      level.value = Uint8(level.value + 3);
      depth.value = Int16(depth.value - 3000);
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          plus,
          Every(Duration(seconds: 1), () {
            Serial.print('count=');
            Serial.print(count.value);
            Serial.print(' ratio=');
            Serial.print(ratio.value);
            Serial.print(' lit=');
            Serial.print(lit.value);
            Serial.print(' level=');
            Serial.print(level.value);
            Serial.print(' depth=');
            Serial.println(depth.value * 1000);
          }),
        ],
      ),
    );
