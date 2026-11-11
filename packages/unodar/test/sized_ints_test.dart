import 'package:test/test.dart';
import 'package:unodar/unodar.dart';

/// The sized types are real Dart, so their wrapping semantics run here. The compiler emits `uint8_t(x)` etc.,
/// and C++ conversion to these types is modulo 2^n (GCC defines the signed case the same way), so these tests
/// pin down the behaviour both sides must share. The fidelity harness re-checks it under avr-gcc.
void main() {
  group('Uint8', () {
    test('keeps in-range values', () => expect([Uint8(0), Uint8(200), Uint8(255)], [0, 200, 255]));
    test('wraps modulo 256', () {
      expect(Uint8(256), 0);
      expect(Uint8(300), 44);
      expect(Uint8(-1), 255);
      expect(Uint8(-256), 0);
    });
    test('is usable in const expressions', () {
      const value = Uint8(511);
      expect(value, 255);
    });
  });

  group('Uint16', () {
    test('keeps in-range values', () => expect([Uint16(0), Uint16(65535)], [0, 65535]));
    test('wraps modulo 65536', () {
      expect(Uint16(65536), 0);
      expect(Uint16(70000), 4464);
      expect(Uint16(-1), 65535);
    });
  });

  group('Int16', () {
    test('keeps in-range values', () => expect([Int16(-32768), Int16(0), Int16(32767)], [-32768, 0, 32767]));
    test('wraps into -32768..32767', () {
      expect(Int16(32768), -32768);
      expect(Int16(40000), -25536);
      expect(Int16(-32769), 32767);
      expect(Int16(65535), -1);
    });
    test('is usable in const expressions', () {
      const value = Int16(40000);
      expect(value, -25536);
    });
  });

  test('reading a sized value gives an int, and arithmetic on it is int arithmetic', () {
    const Uint8 a = Uint8(200);
    const Uint8 b = Uint8(100);
    final int sum = a + b; // Not wrapped: arithmetic happens in int, as it does in int32_t in C++.
    expect(sum, 300);
    expect(Uint8(sum), 44); // Storing back wraps, explicitly.
  });
}
