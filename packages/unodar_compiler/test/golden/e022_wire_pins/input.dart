import 'package:unodar/unodar.dart';

// Wire (I²C) takes A4 (SDA) and A5 (SCL), pins 18 and 19, in a program that uses it (`@CppUsesPins`), so a widget
// there is E022, whether it is written as A4 or as 18. A3 is free.
final sda = Led(pin: A4);
final scl = Button(pin: 19, onPressed: () {});
final spare = Led(pin: A3);

void main() => runDevice(Device(board: Uno(), children: [
      OnStart(() {
        Wire.begin();
      }),
      sda,
      scl,
      spare,
    ]));
