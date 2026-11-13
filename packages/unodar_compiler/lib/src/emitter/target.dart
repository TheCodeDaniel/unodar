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

  /// `arduino-cli compile --build-property` values every sketch must be built with (docs/SUBSET.md "Building").
  List<String> get buildProperties;

  /// Width of C++ `int` on this board. Arithmetic on operands narrower than 32 bits is promoted only to `int`, so on
  /// a 16-bit-`int` board the emitter must widen it to keep Dart's (32-bit, in unodar) results.
  int get nativeIntBits;

  /// Suffix that makes an integer literal `int32_t`-sized (`L`: `long` is 32 bits on AVR).
  String get int32LiteralSuffix;

  /// The C++ spelling of [type].
  String cppType(IrType type);

  /// The facts about the C++ scalar type spelled [name] (`uint8_t`, `unsigned long`, …) that binding parameters and
  /// results may use (`@CppType`, docs/SUBSET.md "Binding C++ classes"), or null if [name] is not one of them.
  CppScalarType? cppScalarType(String name);

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

  /// `-fwrapv` makes signed overflow wrap (defined) instead of undefined behaviour. The AVR core generates code at
  /// link time (`-flto`), so the flag goes to the C and C++ compile steps and to the link step. Property names are
  /// those of `arduino:avr` 1.8.8 `platform.txt`, where they are empty by default.
  @override
  List<String> get buildProperties => const [
        'compiler.c.extra_flags=-fwrapv',
        'compiler.cpp.extra_flags=-fwrapv',
        'compiler.c.elf.extra_flags=-fwrapv',
      ];

  @override
  int get nativeIntBits => 16;

  @override
  String get int32LiteralSuffix => 'L';

  @override
  Set<String> get reservedNames => const {...arduinoAvrNames, ...arduinoExtraNames};

  @override
  CppScalarType? cppScalarType(String name) => _unoScalarTypes[name];

  @override
  String cppType(IrType type) => switch (type) {
        IrType.void_ => 'void',
        IrType.bool_ => 'bool',
        IrType.string => 'const __FlashStringHelper *',
        IrType.int32 => 'int32_t',
        IrType.float32 => 'float',
        IrType.uint8 => 'uint8_t',
        IrType.uint16 => 'uint16_t',
        IrType.int16 => 'int16_t',
      };
}

/// A C++ scalar type that a binding may name with `@CppType`.
final class CppScalarType {
  const CppScalarType.integer(this.name, {required int this.min, required int this.max}) : kind = CppScalarKind.integer;

  const CppScalarType.floatingPoint(this.name)
      : kind = CppScalarKind.floatingPoint,
        min = null,
        max = null;

  const CppScalarType.boolean(this.name)
      : kind = CppScalarKind.boolean,
        min = null,
        max = null;

  final String name;
  final CppScalarKind kind;

  /// The value range of an integer type; null otherwise.
  final int? min;
  final int? max;
}

enum CppScalarKind { integer, floatingPoint, boolean }

/// The accepted `@CppType` spellings with their AVR (avr-gcc) sizes: `int` and `size_t` are 16 bits, `long` 32,
/// `double` is the same 32-bit type as `float`.
const _unoScalarTypes = {
  'bool': CppScalarType.boolean('bool'),
  'float': CppScalarType.floatingPoint('float'),
  'double': CppScalarType.floatingPoint('double'),
  'int8_t': CppScalarType.integer('int8_t', min: -128, max: 127),
  'uint8_t': CppScalarType.integer('uint8_t', min: 0, max: 255),
  'int16_t': CppScalarType.integer('int16_t', min: -32768, max: 32767),
  'uint16_t': CppScalarType.integer('uint16_t', min: 0, max: 65535),
  'int32_t': CppScalarType.integer('int32_t', min: -2147483648, max: 2147483647),
  'uint32_t': CppScalarType.integer('uint32_t', min: 0, max: 4294967295),
  'int': CppScalarType.integer('int', min: -32768, max: 32767),
  'unsigned int': CppScalarType.integer('unsigned int', min: 0, max: 65535),
  'long': CppScalarType.integer('long', min: -2147483648, max: 2147483647),
  'unsigned long': CppScalarType.integer('unsigned long', min: 0, max: 4294967295),
  'size_t': CppScalarType.integer('size_t', min: 0, max: 65535),
};

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
