import 'package:unodar/liquid_crystal.dart';
import 'package:unodar/spi.dart';
import 'package:unodar/unodar.dart';

// SPI takes pins 10 (SS), 11 (MOSI), 12 (MISO) and 13 (SCK) in a program that uses it (`@CppUsesPins`), so widgets
// and `@CppPin` constructor arguments there are E022. Pin 9 is free. A program's own external object can declare
// its pins too: `radio` takes pin 2 because the program uses it.
@CppClass('Radio')
abstract final class Radio {
  external void send(@CppType('uint8_t') int value);
}

@CppUsesPins({2: 'IRQ'})
external final Radio radio;

final led = Led(pin: LED_BUILTIN);
final lcd = LiquidCrystal(12, 11, 5, 4, 3, 7);
final select = Button(pin: 10, onPressed: () {});
final send = Button(
    pin: 9,
    onPressed: () {
      SPI.transfer(1);
      radio.send(2);
    });
final irq = Button(pin: 2, onPressed: () {});

void main() => runDevice(Device(board: Uno(), children: [
      OnStart(() {
        SPI.begin();
      }),
      led,
      select,
      send,
      irq,
    ]));
