import 'package:unodar/unodar.dart';

// OnStart (Phase 6 step 8): a callback that runs once in setup(), at its place in children, before the initial
// delivery of signals. `delay()` is allowed there. Also an avr8js behaviour program: the first OnStart pulses D12 and
// writes a signal before the Led starts; the second switches the Led on after it started; the Watch prints the
// signal once, with the value written in OnStart.
final level = Signal<int>(0);
final led = Led(pin: 13);

void main() => runDevice(Device(board: Uno(), children: [
      OnStart(() {
        pinMode(12, OUTPUT);
        digitalWrite(12, HIGH);
        delay(5);
        digitalWrite(12, LOW);
        level.value = 7;
        Serial.println('start');
      }),
      led,
      OnStart(() {
        led.on();
      }),
      Watch(level, (v) {
        Serial.println(v);
      }),
    ]));
