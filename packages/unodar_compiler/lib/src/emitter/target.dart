import '../ir/ir.dart';
import 'arduino_avr_names.dart';

/// Board-specific facts the emitter needs (PRD §9.10 "Emitter is target-aware by construction").
///
/// Phase 2 adds the integer facts the emitter needs for 32-bit `int` semantics. ESP32 becomes a second
/// implementation in Phase 9.
abstract interface class Target {
  /// Human-readable board name.
  String get name;

  /// Fully qualified board name for `arduino-cli --fqbn`.
  String get fqbn;

  /// Headers every sketch includes, emitted as `#include <...>` in order.
  List<String> get includes;

  /// Width of C++ `int` on this board. Arithmetic on operands narrower than 32 bits is promoted only to `int`, so on
  /// a 16-bit-`int` board the emitter must widen it to keep Dart's (32-bit, in unodar) results.
  int get nativeIntBits;

  /// Suffix that makes an integer literal `int32_t`-sized (`L`: `long` is 32 bits on AVR).
  String get int32LiteralSuffix;

  /// The C++ spelling of [type].
  String cppType(IrType type);

  /// Functions and macros of the board's core and C library that a user name would collide with (E014), beyond
  /// C++ keywords, the unodar API registry, and the all-caps and reserved-pattern rules.
  Set<String> get reservedNames;
}

final class UnoTarget implements Target {
  const UnoTarget();

  @override
  String get name => 'Arduino Uno (ATmega328P)';

  @override
  String get fqbn => 'arduino:avr:uno';

  @override
  List<String> get includes => const ['Arduino.h'];

  @override
  int get nativeIntBits => 16;

  @override
  String get int32LiteralSuffix => 'L';

  @override
  Set<String> get reservedNames => const {...arduinoAvrNames, ...arduinoExtraNames};

  @override
  String cppType(IrType type) => switch (type) {
        IrType.void_ => 'void',
        IrType.bool_ => 'bool',
        IrType.int32 => 'int32_t',
        IrType.float32 => 'float',
        IrType.uint8 => 'uint8_t',
        IrType.uint16 => 'uint16_t',
        IrType.int16 => 'int16_t',
      };
}

/// Names that come from Arduino headers outside `Arduino.h` that sketches commonly include (`wiring_private.h`,
/// the networking classes) and are therefore reserved too. Everything `Arduino.h` itself declares is in the
/// generated [arduinoAvrNames].
const arduinoExtraNames = {
  'Client',
  'IPAddress',
  'Server',
  'Udp',
  'cbi',
  'copysign',
  'isfinite',
  'main',
  'sbi',
  'serialEvent',
};
