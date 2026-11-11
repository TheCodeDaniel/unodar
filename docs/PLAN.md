# Phase 2 plan — language core (done, tagged v0.2.0)

**Status: done.** Every exit-gate item below passed; the release is tagged `v0.2.0`. Phase 3 has not started.

Spec: PRD §8 row 2, the maintainer's Phase 2 brief, `docs/SUBSET.md`. Phase 1 (0.1.0) is complete.
Exit gate: every new golden passes and compiles for `arduino:avr:uno`; the semantic-fidelity decisions are logged
(`DECISIONS.md`) and tested; `SUBSET.md`/`DIAGNOSTICS.md` are accurate; `examples/pulse` builds.

## Steps (one or more small commits each, golden test first) — all done

| # | Step | Test written first |
|---|---|---|
| 1 | Docs: SUBSET, DIAGNOSTICS (E009–E016), DECISIONS, this plan | `docs_test` stays green |
| 2 | `packages/unodar`: `Uint8`, `Uint16`, `Int16` extension types | Dart unit tests of the wrapping semantics |
| 3 | IR + emitter: typed expressions/statements, globals, params/returns, precedence-aware printing, 16-bit widening, `unodar_mod`, prototypes | `emitter_test` on hand-built IR; blink output byte-identical |
| 4 | Diagnostics registry E009–E016, Phase 2 wording for E002–E005 | Phase 1 goldens updated deliberately |
| 5 | Validator relaxation, one construct per commit: top-level vars → expressions/operators + constant evaluator → locals/assignments → `if` → `while` → `for`/`break`/`continue` → user functions/`return` → recursion check (E016) → evaluation order → API arguments | A positive golden and a negative golden per construct |
| 6 | Fidelity harness: `const` vectors, Dart values from the analyzer, `static_assert` under avr-gcc | `fidelity_test` (tagged `arduino`) |
| 7 | arduino-cli compile of **every** positive golden; missing budget = failure | `arduino_compile_test` |
| 8 | Size budgets for the new goldens (dedicated commit with measurements) | `size_budgets.dart` |
| 9 | `examples/pulse` + `tool/check_arduino.sh` builds both examples | CLI build + arduino-cli compile |
| 10 | Final docs pass; `dart analyze && dart format --set-exit-if-changed . && dart test` | — |

## Extension hooks kept
- The IR stays the seam: the emitter never sees the AST.
- Board facts (native `int` width, reserved names, C++ type names) live on `Target`.
- Every new code is in the single registry; the API table now carries C++ parameter types and named parameters.
- Each validator rule owns one construct, so Phase 3+ relaxes them individually.
