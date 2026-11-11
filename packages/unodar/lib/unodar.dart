/// Unodar: Flutter-style Dart for Arduino-class microcontrollers.
///
/// This library is a set of **declarations**. Your code is never run on your computer: the unodar compiler reads
/// it and translates each call into the equivalent Arduino C++. The declarations exist so that autocomplete,
/// documentation, and `dart analyze` work as usual.
///
/// Arduino core: [pinMode], [digitalWrite], [delay], and the constants [HIGH], [LOW], [INPUT], [OUTPUT],
/// [INPUT_PULLUP]. Sized integers: [Uint8], [Uint16], [Int16]. See docs/SUBSET.md for the supported Dart subset.
library;

export 'src/arduino_core.dart';
export 'src/sized_ints.dart';
