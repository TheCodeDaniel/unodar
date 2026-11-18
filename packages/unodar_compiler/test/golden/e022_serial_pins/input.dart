import 'package:unodar/liquid_crystal.dart';
import 'package:unodar/unodar.dart';

// Serial takes pins 0 (RX) and 1 (TX) in a program that uses it: they are the hardware serial port, which is also
// the USB connection. A widget or a `@CppPin` constructor argument there is E022. A program that never names
// `Serial` keeps both pins free (the DHT wrapper links Serial but never opens it, so it does not count).
final status = Led(pin: 1);
final lcd = LiquidCrystal(0, 11, 5, 4, 3, 2);
final report = Button(
    pin: 7,
    onPressed: () {
      Serial.println('pressed');
    });

void main() => runDevice(Device(board: Uno(), children: [status, report]));
