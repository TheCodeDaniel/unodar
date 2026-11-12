import 'package:unodar/unodar.dart';

/// A binding to the AVR core's SoftwareSerial (`SoftwareSerial.h`).
@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppType('uint8_t') int rx, @CppType('uint8_t') int tx, {bool inverse = false});
  external void begin(@CppType('long') int baud);
  external bool listen();
  @CppType('int')
  external int available();
  @CppType('int')
  external int read();
  // Overloads: one Dart name per C++ overload, all mapped to `write` and `print`.
  @CppName('write')
  @CppType('size_t')
  external int writeByte(@CppType('uint8_t') int value);
  @CppName('print')
  @CppType('size_t')
  external int printNumber(@CppType('long') int value);
  @CppName('print')
  @CppType('size_t')
  external int printDouble(double value, {@CppType('int') int digits = 2});
}

/// An existing C++ object reached through its own binding: the hardware serial port, as `HardwareSerial`.
@CppClass('HardwareSerial')
abstract final class Port {
  @CppType('int')
  external int available();
  @CppName('write')
  @CppType('size_t')
  external int send(@CppType('uint8_t') int value);
}

@CppName('Serial')
external final Port usb;

const int rxPin = 10;
final link = SoftSerial(rxPin, rxPin + 1);
final inverted = SoftSerial(8, 9, inverse: true);
int received = 0;

void setup() {
  link.begin(9600);
  inverted.begin(4800);
}

void loop() {
  link.listen();
  if (link.available() > 0) {
    final value = link.read();
    received += value;
    link.writeByte(value);
    usb.send(value ~/ 2);
  }
  final sent = link.printNumber(received * 1000);
  link.printDouble(received / 3, digits: 3);
  if (sent > 5 && usb.available() == 0) {
    link.writeByte(10);
  }
}
