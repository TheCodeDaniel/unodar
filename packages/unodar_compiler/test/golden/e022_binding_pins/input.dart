import 'package:unodar/unodar.dart';

@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppPin() @CppType('uint8_t') int rx, @CppPin() @CppType('uint8_t') int tx);
  external void begin(@CppType('long') int baud);
}

final gps = SoftSerial(2, 3);
final radio = SoftSerial(3, 25);
final button = Button(pin: 2, onPressed: () {});

void main() => runDevice(Device(board: Uno(), children: [button]));
