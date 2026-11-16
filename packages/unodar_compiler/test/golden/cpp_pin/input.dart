import 'package:unodar/unodar.dart';

// @CppPin (Phase 6 step 10): a binding constructor parameter marked as a pin is checked like a widget pin, range
// 0 to 19 and one owner per pin. Here SoftwareSerial's pins 10 and 11 sit next to a Led on 13 and a Button on 4,
// so nothing is reported and the program compiles.
@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppPin() @CppType('uint8_t') int rx, @CppPin() @CppType('uint8_t') int tx);
  external void begin(@CppType('long') int baud);
  @CppName('write')
  @CppType('size_t')
  external int writeByte(@CppType('uint8_t') int value);
}

final link = SoftSerial(10, 11);
final led = Led(pin: 13);

void main() => runDevice(Device(board: Uno(), children: [
      led,
      OnStart(() {
        link.begin(9600);
      }),
      Button(
          pin: 4,
          onPressed: () {
            link.writeByte(65);
            led.toggle();
          }),
    ]));
