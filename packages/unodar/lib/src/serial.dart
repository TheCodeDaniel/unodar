// The Uno's hardware serial port. Arduino's spelling (`Serial`) is kept, which Dart's naming lint would flag.
//
// ignore_for_file: non_constant_identifier_names

/// A hardware serial port (C++ `HardwareSerial`). Use the [Serial] object.
///
/// `print` and `println` take any supported value; the compiler picks the C++ overload from the argument's static
/// type (docs/SUBSET.md "Serial"): a string literal is stored in flash (`F("…")`), a `bool` prints `true`/`false`,
/// an `int` prints in decimal, and a `double` prints with [digits] decimals in Arduino's format.
abstract final class HardwareSerial {
  /// Opens the port at [baud] bits per second, e.g. 9600. Compiles to `Serial.begin(baud)`.
  external void begin(int baud);

  /// Sends [value] as text. A string must be a literal. [digits] applies to a `double` only.
  external void print(Object value, {int digits = 2});

  /// Like [print], then a line break. `Serial.println('')` sends only the line break.
  external void println(Object value, {int digits = 2});
}

/// The serial port on pins 0 and 1, which is also the USB connection. Compiles to C++ `Serial`.
external final HardwareSerial Serial;
