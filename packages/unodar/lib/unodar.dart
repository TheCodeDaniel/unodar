/// Unodar: Flutter-style Dart for Arduino-class microcontrollers.
///
/// This library is a set of **declarations**. Your code is never run on your computer: the unodar compiler reads
/// it and translates each call into the equivalent Arduino C++. The declarations exist so that autocomplete,
/// documentation, and `dart analyze` work as usual.
///
/// * Arduino core: [pinMode], [digitalWrite], [digitalRead], [analogRead], [analogWrite], [delay], [millis],
///   [micros], and the constants [HIGH], [LOW], [INPUT], [OUTPUT], [INPUT_PULLUP], [A0]…[A5], [LED_BUILTIN].
/// * [Serial], the hardware serial port.
/// * Sized integers: [Uint8], [Uint16], [Int16].
/// * Bindings: [Wire] (I²C) and [Servo].
/// * Interop: [CppClass], [CppHeader], [CppName], [CppType], [CppInclude], and the escape hatch [cpp].
///
/// See docs/SUBSET.md for the supported Dart subset.
library;

export 'src/arduino_core.dart';
export 'src/interop.dart';
export 'src/serial.dart';
export 'src/servo.dart';
export 'src/sized_ints.dart';
export 'src/wire.dart';
