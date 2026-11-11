import '../ir/ir.dart';

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
  Set<String> get reservedNames => arduinoAvrReservedNames;

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

/// Lower- and mixed-case names defined by the Arduino AVR core (Arduino.h, WCharacter.h, WString.h, the serial
/// classes) and the parts of avr-libc it includes (math.h, stdlib.h, string.h, stdio.h). Function-like macros
/// (`min`, `max`, `abs`, `round`, `sq`, `constrain`, `bit`, …) would rewrite a user identifier; the functions would
/// clash at compile or link time (`init`, `map`, `random`, `yield`, …). ALL-CAPS macros are covered by their own
/// rule and not repeated here.
const arduinoAvrReservedNames = {
  // Arduino.h macros and inline helpers.
  'min', 'max', 'abs', 'constrain', 'round', 'radians', 'degrees', 'sq', 'bit', 'bitRead', 'bitSet', 'bitClear', //
  'bitWrite', 'bitToggle', 'lowByte', 'highByte', 'word', 'makeWord', 'byte', 'boolean', 'interrupts',
  'noInterrupts', 'sei', 'cli', 'sbi', 'cbi', 'clockCyclesPerMicrosecond', 'clockCyclesToMicroseconds',
  'microsecondsToClockCycles', 'digitalPinToPort', 'digitalPinToBitMask', 'digitalPinToTimer',
  'analogInPinToBit', 'analogInputToDigitalPin', 'portOutputRegister', 'portInputRegister', 'portModeRegister',
  'digitalPinToInterrupt', 'digitalPinHasPWM',
  // Arduino core functions.
  'init', 'initVariant', 'main', 'yield', 'serialEvent', 'serialEventRun', 'millis', 'micros', 'delay',
  'delayMicroseconds', 'pinMode', 'digitalWrite', 'digitalRead', 'analogRead', 'analogWrite', 'analogReference',
  'tone', 'noTone', 'pulseIn', 'pulseInLong', 'shiftIn', 'shiftOut', 'attachInterrupt', 'detachInterrupt',
  'random', 'randomSeed', 'map', 'setup', 'loop',
  // WCharacter.h.
  'isAlphaNumeric', 'isAlpha', 'isAscii', 'isWhitespace', 'isControl', 'isDigit', 'isGraph', 'isLowerCase',
  'isPrintable', 'isPunct', 'isSpace', 'isUpperCase', 'isHexadecimalDigit', 'toAscii', 'toLowerCase', 'toUpperCase',
  // Core classes and objects.
  'String', 'Serial', 'Print', 'Printable', 'Stream', 'HardwareSerial', 'IPAddress', 'Client', 'Server', 'Udp',
  // avr-libc math.h.
  'acos', 'asin', 'atan', 'atan2', 'cbrt', 'ceil', 'copysign', 'cos', 'cosh', 'exp', 'fabs', 'fdim', 'floor', 'fma',
  'fmax', 'fmin', 'fmod', 'frexp', 'hypot', 'isfinite', 'isinf', 'isnan', 'ldexp', 'log', 'log10', 'lrint',
  'lround', 'modf', 'pow', 'signbit', 'sin', 'sinh', 'sqrt', 'square', 'tan', 'tanh', 'trunc',
  // avr-libc stdlib.h, string.h, stdio.h.
  'atoi', 'atol', 'atof', 'strtol', 'strtoul', 'strtod', 'rand', 'srand', 'malloc', 'free', 'calloc', 'realloc',
  'exit', 'abort', 'qsort', 'bsearch', 'div', 'ldiv', 'labs', 'itoa', 'ltoa', 'utoa', 'ultoa', 'dtostrf', 'dtostre',
  'memcpy', 'memset', 'memcmp', 'memmove', 'strlen', 'strcmp', 'strncmp', 'strcpy', 'strncpy', 'strcat', 'strchr',
  'printf', 'sprintf', 'snprintf', 'puts', 'putchar', 'getchar',
};
