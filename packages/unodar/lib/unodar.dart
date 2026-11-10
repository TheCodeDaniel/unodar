/// Unodar: Flutter-style Dart for Arduino-class microcontrollers.
///
/// This library is a set of **declarations**. Your code is never run on your computer: the unodar compiler reads
/// it and translates each call into the equivalent Arduino C++. The declarations exist so that autocomplete,
/// documentation, and `dart analyze` work as usual.
///
/// Phase 1 supports exactly: [pinMode], [digitalWrite], [delay], and the constants [HIGH], [LOW], [INPUT],
/// [OUTPUT], [INPUT_PULLUP], used inside top-level `void setup()` and `void loop()` functions.
library;

export 'src/arduino_core.dart';
