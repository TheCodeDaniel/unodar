/// Board-specific facts the emitter needs (PRD §9.10 "Emitter is target-aware by construction").
///
/// Phase 1 has one implementation. Integer widths, extra includes, and memory policy (e.g. flash strings) will be
/// added here as later phases need them; ESP32 becomes a second implementation in Phase 9.
abstract interface class Target {
  /// Human-readable board name.
  String get name;

  /// Fully qualified board name for `arduino-cli --fqbn`.
  String get fqbn;

  /// Headers every sketch includes, emitted as `#include <...>` in order.
  List<String> get includes;
}

final class UnoTarget implements Target {
  const UnoTarget();

  @override
  String get name => 'Arduino Uno (ATmega328P)';

  @override
  String get fqbn => 'arduino:avr:uno';

  @override
  List<String> get includes => const ['Arduino.h'];
}
