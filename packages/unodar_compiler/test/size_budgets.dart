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
  // Re-measured 2026-11-12 (Phase 3 review): 762 B since every sketch is built with -fwrapv (d213602); the 4 B
  // difference appeared with that change and was not analysed further. Limit unchanged (762 + 30 % rounds up to 1000).
  'sized_types': SizeBudget(baselineFlash: 762, baselineRam: 14, maxFlash: 1000, maxRam: 25),
  // subset_features is the Phase 1 golden that never had a budget; measured now with the Phase 2 emitter, whose
  // output for it is byte-identical to Phase 1.
  'subset_features': SizeBudget(baselineFlash: 902, baselineRam: 9, maxFlash: 1200, maxRam: 20),
  'while_loop': SizeBudget(baselineFlash: 812, baselineRam: 13, maxFlash: 1100, maxRam: 24),

  // Phase 3, 2026-11-12, arduino-cli 1.5.1, arduino:avr 1.8.8, Servo 1.3.0, built with -fwrapv. Same limit rule as
  // Phase 2. First measured with their goldens (docs/DECISIONS.md) and reviewed together in step 9: every one
  // re-measured equal to its baseline except core_io.
  //
  // RAM is the scarce resource on the Uno (2048 B), and it is fixed at build time: arduino-cli's `data` figure is
  // all static allocation, mostly library buffers (docs/SUBSET.md "Libraries reserve RAM"). Per binding golden:
  //   serial_print 204 B, named_arguments 200 B   Serial: 64-byte receive + 64-byte transmit buffers
  //   user_binding 348 B                          two SoftwareSerial objects, their shared 64-byte buffer, Serial
  //   wire 408 B                                  TwoWire + twi.c 32-byte buffers, Serial
  //   servo 57 B                                  Servo's table for 12 servos
  // The +11 B RAM margin catches any new static state the compiler starts emitting.
  //
  // core_io links analogRead/analogWrite (wiring_analog.c) and micros(). Its baseline moves from 1740 B to 1804 B
  // because the E013 commit (41393d0) added `analogRead(A4) + lastToggle` and an `if` to the golden: more input,
  // not larger output per construct. The limit follows the rule from the new baseline: 1804 + 30 % = 2345, rounded
  // up to 2350 (was 2300).
  'core_io': SizeBudget(baselineFlash: 1804, baselineRam: 14, maxFlash: 2350, maxRam: 25),
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

  // Phase 4, 2026-11-13, arduino-cli 1.5.1, arduino:avr 1.8.8, built with -fwrapv. Same limit rule. First measured
  // with their goldens and reviewed together in step 8: every one re-measured equal to its baseline.
  //
  // Widget objects are constant-initialized globals from unodar_widgets.h. Their sizes are static_asserted by the
  // runtime's own test sketch (test/runtime/widgets/widgets.ino): Led 2 B (pin, state), Button 7 B (pin, two flags,
  // a uint32_t timestamp), Every 8 B (interval, last tick). Per widget golden:
  //   widget_led 15 B                            the core's 9 B (as blink) + three Leds (6 B)
  //   widget_serial, widget_serial_baud 186 B    a program using Serial (its 64-byte buffers) + one Led
  //   widget_button 208 B                        Serial + one Led + two Buttons (14 B) + an int counter
  //   widget_every 218 B                         Serial + one Led + three Everys (24 B) + an int counter
  // A widget program costs its objects and nothing else in RAM: no tables, no heap, no function pointers.
  //
  // widget_led: three Led objects and their begin() calls; smaller than blink, which links delay().
  'widget_led': SizeBudget(baselineFlash: 808, baselineRam: 15, maxFlash: 1100, maxRam: 26),
  // widget_serial, widget_serial_baud: Serial opened by the generated setup(). The two measure the same.
  'widget_serial': SizeBudget(baselineFlash: 1734, baselineRam: 186, maxFlash: 2300, maxRam: 197),
  'widget_serial_baud': SizeBudget(baselineFlash: 1734, baselineRam: 186, maxFlash: 2300, maxRam: 197),
  // widget_button: the debounce logic, two callbacks, and Print's integer printing.
  'widget_button': SizeBudget(baselineFlash: 2662, baselineRam: 208, maxFlash: 3500, maxRam: 219),
  // widget_every: three timers and their callbacks.
  'widget_every': SizeBudget(baselineFlash: 2392, baselineRam: 218, maxFlash: 3150, maxRam: 229),

  // Fix found in Phase 5 step 4, 2026-11-14, same tool versions and limit rule; a first measurement of a new golden.
  // bound_object_conversion: a Led whose pin is `Uint8(ledPin)` (the conversion is parenthesized in the C++
  // declaration) and an Every; like widget_led plus a timer, no Serial.
  'bound_object_conversion': SizeBudget(baselineFlash: 940, baselineRam: 19, maxFlash: 1250, maxRam: 30),
};
