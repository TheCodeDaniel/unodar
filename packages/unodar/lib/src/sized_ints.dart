// Sized integer types (Phase 2). Unodar `int` is a 32-bit `int32_t` in C++; these types let a program store a
// value in 8 or 16 bits, which matters on the Uno's 2 KB of RAM.
//
// Each type is an extension type over `int` that `implements int`:
//   * reading a value widens it to `int` losslessly, so it works anywhere an `int` is expected;
//   * arithmetic on it is `int` arithmetic (`Uint8 + Uint8` is an `int`, computed in `int32_t` in C++);
//   * storing an `int` back needs the explicit constructor, which wraps exactly like the C++ conversion
//     (`Uint8(300) == 44`). Assigning an `int` without it is a Dart type error, so a value never changes width
//     invisibly.
//
// Unlike the Arduino declarations, this file is real, executable Dart: the wrapping is defined here and tested,
// and the compiler emits the C++ conversion with the same result (`uint8_t(x)`, `uint16_t(x)`, `int16_t(x)`).

/// An unsigned 8-bit integer, 0 to 255. Compiles to C++ `uint8_t`.
extension type const Uint8._(int _value) implements int {
  /// [value] wrapped into 0..255 (modulo 256), e.g. `Uint8(300) == 44`, `Uint8(-1) == 255`.
  const Uint8(int value) : this._(value & 0xFF);
}

/// An unsigned 16-bit integer, 0 to 65535. Compiles to C++ `uint16_t`.
extension type const Uint16._(int _value) implements int {
  /// [value] wrapped into 0..65535 (modulo 65536), e.g. `Uint16(-1) == 65535`.
  const Uint16(int value) : this._(value & 0xFFFF);
}

/// A signed 16-bit integer, -32768 to 32767. Compiles to C++ `int16_t`.
extension type const Int16._(int _value) implements int {
  /// [value] wrapped into -32768..32767 (modulo 65536), e.g. `Int16(40000) == -25536`.
  const Int16(int value) : this._(((value + 0x8000) & 0xFFFF) - 0x8000);
}
