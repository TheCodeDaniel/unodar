import 'package:test/test.dart';
import 'package:unodar/unodar.dart';

/// The constants are real Dart values so user code type-checks under `dart analyze`. The compiler emits them by
/// name (never by value), but the values still mirror Arduino.h so that the Dart view and the C++ view agree.
void main() {
  test('pin levels and modes mirror Arduino.h', () {
    expect([LOW, HIGH], [0, 1]);
    expect([INPUT, OUTPUT, INPUT_PULLUP], [0, 1, 2]);
  });
}
