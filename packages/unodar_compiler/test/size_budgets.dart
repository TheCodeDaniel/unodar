/// Size budgets for generated sketches on the Arduino Uno (PRD §11, "size budget … enforced in CI").
///
/// POLICY: these numbers change only in a dedicated commit whose message explains *why* the generated code
/// legitimately grew (or shrank) and shows the new arduino-cli measurement. Never raise a limit to make a failing
/// test pass in the same commit as an unrelated change. A failing budget test means the compiler started emitting
/// more code or more RAM than before; find out why first.
///
/// `flash` is the `text` section and `ram` the `data` section reported by
/// `arduino-cli compile --fqbn arduino:avr:uno --format json` (builder_result.executable_sections_size).
library;

final class SizeBudget {
  const SizeBudget({
    required this.baselineFlash,
    required this.baselineRam,
    required this.maxFlash,
    required this.maxRam,
  });

  /// Measured when the budget was set. Informational: the test reports drift against it.
  final int baselineFlash;
  final int baselineRam;

  /// Hard limits, in bytes. The test fails above these.
  final int maxFlash;
  final int maxRam;
}

/// Budgets per golden case, keyed by directory name under test/golden/.
const sizeBudgets = <String, SizeBudget>{
  // Phase 1 baseline, measured 2026-11-10 with arduino-cli 1.5.1 and arduino:avr 1.8.8.
  // Most of the 924 B is the Arduino core (init, timer0 ISR for millis/delay, pin tables), not unodar output.
  'blink': SizeBudget(baselineFlash: 924, baselineRam: 9, maxFlash: 1200, maxRam: 20),

  // Phase 2 baselines, measured 2026-11-11 with arduino-cli 1.5.1 and arduino:avr 1.8.8 (same tool versions as
  // blink). Limits follow blink's rule: flash max = baseline + 30 %, rounded up to 50 B; RAM max = baseline + 11 B.
  // These are first measurements of new goldens, not raises of existing budgets.
  // `doubles` is the largest: it links the AVR soft-float routines (float add/mul/div/compare, int<->float).
  'api_arguments': SizeBudget(baselineFlash: 1006, baselineRam: 9, maxFlash: 1350, maxRam: 20),
  'doubles': SizeBudget(baselineFlash: 1838, baselineRam: 13, maxFlash: 2400, maxRam: 24),
  'expressions': SizeBudget(baselineFlash: 548, baselineRam: 9, maxFlash: 750, maxRam: 20),
  'for_loop': SizeBudget(baselineFlash: 882, baselineRam: 13, maxFlash: 1150, maxRam: 24),
  'functions': SizeBudget(baselineFlash: 994, baselineRam: 9, maxFlash: 1300, maxRam: 20),
  'globals': SizeBudget(baselineFlash: 1436, baselineRam: 23, maxFlash: 1900, maxRam: 34),
  'if_else': SizeBudget(baselineFlash: 1112, baselineRam: 13, maxFlash: 1450, maxRam: 24),
  'locals_assignments': SizeBudget(baselineFlash: 634, baselineRam: 13, maxFlash: 850, maxRam: 24),
  'pulse': SizeBudget(baselineFlash: 1106, baselineRam: 13, maxFlash: 1450, maxRam: 24),
  'sized_types': SizeBudget(baselineFlash: 766, baselineRam: 14, maxFlash: 1000, maxRam: 25),
  // subset_features is the Phase 1 golden that never had a budget; measured now with the Phase 2 emitter, whose
  // output for it is byte-identical to Phase 1.
  'subset_features': SizeBudget(baselineFlash: 902, baselineRam: 9, maxFlash: 1200, maxRam: 20),
  'while_loop': SizeBudget(baselineFlash: 812, baselineRam: 13, maxFlash: 1100, maxRam: 24),

  // Phase 3 first measurements, 2026-11-12, arduino-cli 1.5.1, arduino:avr 1.8.8, built with -fwrapv. Same limit
  // rule as Phase 2. Each lands with its golden (docs/DECISIONS.md); step 9 reviews them together.
  // core_io links analogRead/analogWrite (wiring_analog.c) and micros().
  'core_io': SizeBudget(baselineFlash: 1740, baselineRam: 14, maxFlash: 2300, maxRam: 25),
  // serial_print links HardwareSerial and Print (incl. printFloat and the soft-float routines); its 204 B RAM is
  // mostly Serial's 64-byte receive and transmit buffers.
  'serial_print': SizeBudget(baselineFlash: 4154, baselineRam: 204, maxFlash: 5450, maxRam: 215),
  'named_arguments': SizeBudget(baselineFlash: 3624, baselineRam: 200, maxFlash: 4750, maxRam: 211),
  // user_binding: two SoftwareSerial objects (64-byte shared receive buffer, per-object state) plus Serial, which
  // the `usb` binding reaches; RAM 348 B of 2048 B.
  'user_binding': SizeBudget(baselineFlash: 5038, baselineRam: 348, maxFlash: 6550, maxRam: 359),
  // wire: TwoWire and twi.c keep five 32-byte buffers, plus Serial's two 64-byte buffers; RAM 408 B of 2048 B.
  'wire': SizeBudget(baselineFlash: 4536, baselineRam: 408, maxFlash: 5900, maxRam: 419),
  // servo: Servo.cpp's timer1 ISR and its table of 12 servos; RAM 57 B of 2048 B.
  'servo': SizeBudget(baselineFlash: 2724, baselineRam: 57, maxFlash: 3550, maxRam: 68),
  'cpp_escape_hatch': SizeBudget(baselineFlash: 1124, baselineRam: 13, maxFlash: 1500, maxRam: 24),
};
