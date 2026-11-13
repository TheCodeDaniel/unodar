# Phase 4 plan — static widget tree

**Status: done (2026-11-13), on the `phase-4` branch, awaiting maintainer review and the v0.4.0 tag.** Approved by
the maintainer and built step by step. Step 6 ran in the order a, f, b, c, d, e (Serial auto-begin before
callbacks; see DECISIONS). Phase 5 (Signals) is out of scope.

Final state: 325 tests (16 in `packages/unodar`, 309 in `packages/unodar_compiler`), 112 goldens (25 positive,
each compiled with arduino-cli, size-budgeted, and checked heap-free), the widget runtime header tested on its own
in avr8js with negative controls, the goal program run in avr8js (debounced presses, tick count) with a negative
control, and `examples/button_led`.

Spec: PRD §7, §8 row 4, §10, `docs/SUBSET.md` "Widgets: `runDevice`", `docs/DIAGNOSTICS.md` (E008, E012, E021–E023)
and the 2026-11-13 entries in `docs/DECISIONS.md` (maintainer decisions on Button, Every, `delay()`, and PRD §13.2).
Exit gate: the goal program (`examples/button_led`) compiles to flat, heap-free C++ and, in avr8js, a debounced
press toggles the LED and `Every` ticks the expected number of times; every new positive golden compiles, has a
size budget and passes the no-heap check; every rejection has a negative golden; the docs are accurate.

## Steps (one or more small commits each, test first)

| # | Step | Test written first |
|---|---|---|
| 1 | Docs: SUBSET, DIAGNOSTICS (E008, E012, E021–E023), DECISIONS, this plan; PRD version column and §13.2 | `docs_test` stays green (new E008 example waits in `docs/drafts`) |
| 2 | `packages/unodar`: `Widget`, `Board`, `Uno`, `Device`, `runDevice`, `Led` (`on`/`off`/`toggle`), `Button`, `Every` | `api_surface_test` |
| 3 | `runtime/unodar_widgets.h`: `unodar::Led`, `Button` (pull-up, 50 ms debounce, press edge), `Every` (drift-free, wrap-safe, one tick per pass), `constexpr` constructors; embedded in the compiler | avr8js tests of a hand-written sketch using the `now` overloads (debounce with bounce, held at boot, Every count, drift, catch-up, 2^32 wrap); header-equality test |
| 4 | avr8js runner: scheduled pin inputs and output-pin change log | Runner test on a hand-written sketch |
| 5 | IR + emitter + CLI: sketch-local include; `CompileSuccess` carries extra files; `unodar build` writes `unodar_widgets.h`; test helpers copy it | `emitter_test`, `cli_test`; existing goldens byte-identical |
| 6 | Validator + lowering, one construct per commit with positive and negative goldens: (a) `main()`/`runDevice`/`Device` shape and `Led` (E008, E021); (b) `Button` and callbacks (E012); (c) `Every` and `Duration`; (d) the remaining E022 rules (pins, children, order, handles); (e) E023 (call-graph check); (f) Serial auto-begin and `serialBaud`, `Serial.begin` rejected | Goldens; `arduino_compile_test` (compile, budget, no heap) |
| 7 | Behaviour tests in avr8js on the goal program: a bouncing press toggles pin 13 exactly once per press; `Every(500 ms)` prints `tick` exactly N times in a fixed simulated time | `runtime_fidelity_test` (tagged `arduino`) |
| 8 | Size-budget review (dedicated commit, RAM per widget golden) | `size_budgets.dart` |
| 9 | `examples/button_led` (the goal program) with `wokwi/` (diagram, README, serial monitor), built by `tool/check_arduino.sh` and run in avr8js | CLI build + arduino-cli compile |
| 10 | Final docs pass (README status and known limits, PRD status, PLAN); full check suite; end report | — |

## Extension hooks kept
- Widgets lower into the existing IR (bound objects, functions, method calls), so Phase 5 signals and Phase 8
  display widgets add IR-level behaviour, not a parallel code path.
- The widget table is data (registry rows: C++ class, setup call, poll call, callback parameters), so new widgets
  are rows plus runtime structs.
- The runtime header is plain C++ with `now` overloads, testable without the compiler.
