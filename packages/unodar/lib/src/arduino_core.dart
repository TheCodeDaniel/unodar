// Arduino core API (Phase 1 slice).
//
// Names deliberately keep Arduino's spelling (UPPER_CASE constants, camelCase functions) so that tutorials,
// datasheets, and the generated C++ all read the same way. That conflicts with Dart's constant naming lint, which
// is disabled for this file only.
//
// ignore_for_file: constant_identifier_names

/// Digital logic level: low (0 V). Use with [digitalWrite].
const int LOW = 0;

/// Digital logic level: high (supply voltage). Use with [digitalWrite].
const int HIGH = 1;

/// Pin mode: high-impedance input. Use with [pinMode].
const int INPUT = 0;

/// Pin mode: output that can drive a load such as an LED. Use with [pinMode].
const int OUTPUT = 1;

/// Pin mode: input with the internal pull-up resistor enabled. Use with [pinMode].
const int INPUT_PULLUP = 2;

/// Configures [pin] to behave as an input or output.
///
/// [mode] is one of [INPUT], [OUTPUT], or [INPUT_PULLUP]. Compiles to Arduino's `pinMode(pin, mode)`.
external void pinMode(int pin, int mode);

/// Drives digital [pin] to [value], which is [HIGH] or [LOW].
///
/// The pin must first be configured with `pinMode(pin, OUTPUT)`. Compiles to `digitalWrite(pin, value)`.
external void digitalWrite(int pin, int value);

/// Pauses the program for [ms] milliseconds. Compiles to Arduino's `delay(ms)`.
external void delay(int ms);
