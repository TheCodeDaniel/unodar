import 'package:test/test.dart';
import 'package:unodar/unodar.dart';

/// The constants are real Dart values so user code type-checks under `dart analyze`. The compiler emits them by
/// name (never by value), but the values still mirror Arduino.h so that the Dart view and the C++ view agree.
void main() {
  test('pin levels and modes mirror Arduino.h', () {
    expect([LOW, HIGH], [0, 1]);
    expect([INPUT, OUTPUT, INPUT_PULLUP], [0, 1, 2]);
  });

  test('analog pins and LED_BUILTIN mirror the Uno pins_arduino.h (variants/standard)', () {
    expect([A0, A1, A2, A3, A4, A5], [14, 15, 16, 17, 18, 19]);
    expect(LED_BUILTIN, 13);
  });

  test('interop annotations are const and keep their argument', () {
    const header = CppHeader('Servo.h');
    const cppClass = CppClass('Servo');
    const name = CppName('write');
    const type = CppType('uint8_t');
    const include = CppInclude('avr/wdt.h');
    expect([header.header, cppClass.name, name.name, type.type, include.header],
        ['Servo.h', 'Servo', 'write', 'uint8_t', 'avr/wdt.h']);
  });
}
