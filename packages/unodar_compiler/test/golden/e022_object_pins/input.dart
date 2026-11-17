import 'package:unodar/spi.dart';
import 'package:unodar/unodar.dart';

// Two external objects that a program uses may not take the same pin (`@CppUsesPins`). Reported once per pair, at
// the first use of the object used later, with every pin they share. `beeper` and `radio` share pin 2; `display`
// shares 12 and 13 with SPI; pin 3 of `beeper` is its own.
@CppClass('Display')
abstract final class Display {
  external void show(@CppType('uint8_t') int value);
}

@CppClass('Radio')
abstract final class Radio {
  external void send(@CppType('uint8_t') int value);
}

@CppUsesPins({12: 'DATA', 13: 'CLK'})
external final Display display;

@CppUsesPins({2: 'IRQ'})
external final Radio radio;

@CppUsesPins({2: 'OUT', 3: 'EN'})
external final Radio beeper;

void setup() {
  SPI.begin();
  radio.send(1);
}

void loop() {
  display.show(2);
  beeper.send(3);
}
