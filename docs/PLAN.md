# Phase 3 plan — hardware API and interop foundation

**Status: planned, awaiting maintainer approval.** Phase 2 is done (tagged `v0.2.0`). Phase 4 (widgets) is out of
scope.

Spec: PRD §8 row 3, the maintainer's Phase 3 brief, `docs/SUBSET.md`, `docs/DIAGNOSTICS.md` (E017–E020), and the
2026-11-12 entries in `docs/DECISIONS.md` (including the four maintainer decisions).
Exit gate: every new golden passes, compiles for `arduino:avr:uno` (Servo installed), and has a size budget; every
rejection has a negative golden; no generated output uses the heap; the runtime fidelity harness passes in avr8js
with its negative control failing; `SUBSET.md`/`DIAGNOSTICS.md` are accurate; the examples build.

## Steps (one or more small commits each, golden test first)

| # | Step | Test written first |
|---|---|---|
| 1 | Docs: SUBSET, DIAGNOSTICS (E017–E020), DECISIONS, this plan | `docs_test` stays green |
| 2 | `packages/unodar`: `digitalRead`, `analogRead`, `analogWrite`, `millis`, `micros`, `A0`–`A5`, `LED_BUILTIN`; `Serial`; annotations `CppHeader`, `CppClass`, `CppName`, `CppType`, `CppInclude`; `cpp()`; the Wire and Servo bindings | `api_surface_test` (values mirror `pins_arduino.h`) |
| 3 | Registry: return types, C++ result types, objects and methods, named parameters with defaults; the binding reader (annotations → registry rows) | Unit tests on the registry and the reader |
| 4 | IR + emitter: string literal (`F()`), method call, bound global (with constructor arguments), raw C++ statement, program includes; result widening | `emitter_test` on hand-built IR; existing goldens byte-identical |
| 5 | Validator relaxation, one construct per commit, each with positive and negative goldens: `core_io` → `serial_print` (strings) → `named_arguments` → `user_binding` (SoftwareSerial, constructor arguments, `@CppName`) → `wire` → `servo` → `cpp_escape_hatch` (`@CppInclude`); E013 tightening | Goldens; `arduino_compile_test` |
| 6 | Servo: `tool/check_arduino.sh` fails with the install command, the test gate checks it, CI installs `Servo@1.3.0` (done before the Servo golden, see DECISIONS) | Gate test with the library missing (`toolchain_gate_test`) |
| 7 | No-heap check over every positive golden's output | New test in `arduino_compile_test` or its own file |
| 8 | **Done.** Runtime fidelity harness: unodar fixture with unfoldable inputs (`analogRead`, `millis`, `micros`) and identities that hold for every input, plus subtraction across the INT32_MAX/INT32_MIN boundary with operands only known at runtime (`volatile`), run by the avr8js runner in `tool/avr_runner/` (pinned version, lockfile; fixed cycle count, USART capture, PASS/FAIL lines); a negative control built without `-fwrapv` must print FAIL; CI installs Node with `actions/setup-node` | `runtime_fidelity_test` (tagged `arduino`) |
| 9 | Size budgets for the new goldens (dedicated commit with measurements) | `size_budgets.dart` |
| 10 | `examples/` sketch for Phase 3, built by `tool/check_arduino.sh` | CLI build + arduino-cli compile |
| 11 | Optional: drop the `L` suffix where the E010 evaluation proves a constant operation fits a 16-bit `int` (deliberate golden updates, own commit) | Goldens |
| 12 | Final docs pass (README status, PRD status line); `dart analyze && dart format --set-exit-if-changed . && dart test`; end report | — |

## Extension hooks kept
- The IR stays the seam: bindings, strings, and raw C++ become IR nodes; the emitter never sees the AST.
- The registry stays the single API table; bindings are data read from annotations, not code paths per library.
- C++ type facts (widths, ranges for `@CppType`, promotions) live on `Target`, ready for ESP32 (Phase 9).
- Bound objects are plain globals, which Phase 4 widgets can own the same way.
