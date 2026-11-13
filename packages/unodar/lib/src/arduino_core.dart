// Arduino core API (Phase 3 slice: digital and analog I/O, timing).
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

/// Analog input pin 0 (14 on the Uno). Usable with [analogRead], and as a digital pin.
const int A0 = 14;

/// Analog input pin 1 (15 on the Uno).
const int A1 = 15;

/// Analog input pin 2 (16 on the Uno).
const int A2 = 16;

/// Analog input pin 3 (17 on the Uno).
const int A3 = 17;

/// Analog input pin 4 (18 on the Uno; also I²C SDA).
const int A4 = 18;

/// Analog input pin 5 (19 on the Uno; also I²C SCL).
const int A5 = 19;

/// The pin of the on-board LED (13 on the Uno).
const int LED_BUILTIN = 13;

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

/// Reads digital [pin]: [HIGH] or [LOW]. Compiles to `digitalRead(pin)`.
external int digitalRead(int pin);

/// Reads analog [pin] (e.g. [A0]): 0 to 1023 for 0 V to the reference voltage. Compiles to `analogRead(pin)`.
external int analogRead(int pin);

/// Writes a PWM duty cycle [value] (0 to 255) to [pin]. Only PWM pins (3, 5, 6, 9, 10, 11 on the Uno) produce PWM.
/// Compiles to `analogWrite(pin, value)`.
external void analogWrite(int pin, int value);

/// Milliseconds since the board started. Compiles to `int32_t(millis())`.
///
/// After about 24.8 days the value passes 2147483647 and continues at -2147483648. Elapsed time stays correct
/// across that wrap: `if (now - last >= interval)` works, because subtraction wraps too (sketches are built with
/// `-fwrapv`). Comparing two readings directly (`now > last`) does not. See docs/SUBSET.md.
external int millis();

/// Microseconds since the board started, in steps of 4 µs on the Uno. Compiles to `int32_t(micros())`.
///
/// Wraps like [millis], after about 35.8 minutes; `now - last >= interval` stays correct across the wrap.
external int micros();
