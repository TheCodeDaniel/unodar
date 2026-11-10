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
};
