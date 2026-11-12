// The Wire (I²C) binding. Wire ships with the Arduino AVR core. Arduino's spelling (`Wire`) is kept.
//
// ignore_for_file: non_constant_identifier_names

import 'interop.dart';

/// The I²C bus (C++ `TwoWire`, from `Wire.h`). Use the [Wire] object; this class has no constructor.
@CppHeader('Wire.h')
@CppClass('TwoWire')
abstract final class TwoWire {
  /// Joins the bus as the controller.
  external void begin();

  /// Sets the bus clock in Hz, e.g. 400000.
  external void setClock(@CppType('uint32_t') int frequency);

  /// Starts a write to the device at 7-bit [address].
  external void beginTransmission(@CppType('uint8_t') int address);

  /// Queues one byte for the current transmission. Returns the number of bytes queued (1, or 0 if full).
  @CppType('size_t')
  external int write(@CppType('uint8_t') int value);

  /// Sends the queued bytes. Returns 0 on success, otherwise an Arduino error code (1 to 5).
  @CppType('uint8_t')
  external int endTransmission();

  /// Reads [quantity] bytes from the device at [address] into the receive buffer. Returns the number received.
  @CppType('uint8_t')
  external int requestFrom(@CppType('int') int address, @CppType('int') int quantity);

  /// The number of received bytes not read yet.
  @CppType('int')
  external int available();

  /// The next received byte, or -1 if there is none.
  @CppType('int')
  external int read();
}

/// The Uno's I²C bus (A4 = SDA, A5 = SCL). Compiles to C++ `Wire`.
external final TwoWire Wire;
