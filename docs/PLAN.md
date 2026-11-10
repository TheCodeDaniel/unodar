# Phase 1 plan — walking skeleton (target 0.1)

Spec: PRD §9. Exit gate: all seven acceptance criteria in PRD §9.9.

## Steps (one commit each, test first)

| # | Step | Test written first |
|---|---|---|
| 1 | Scaffold pub workspace, configs, docs skeleton | `dart analyze` / `dart format` clean |
| 2 | `packages/unodar` Arduino core declarations | pubspec has no `analyzer`/`flutter` dependency |
| 3 | Central diagnostics registry (E001–E008) + formatter | unit: `file:line:col: error[E00x]: …` format |
| 4 | Golden harness + hand-written blink golden (red) | `golden_test.dart` over `test/golden/*/` |
| 5 | IR, `Target`/`UnoTarget`, C++ emitter with `#line` | unit: hand-built IR → exact blink C++ |
| 6 | Analyzer frontend; analysis errors → E007 | golden `e007_type_error` |
| 7 | Data-driven API registry, composable validator, lowering | blink golden green |
| 8 | Negative goldens E001–E006, E008 | one golden per required case |
| 9 | CLI `build` (+ `--help`, exit codes 0/1/2), `examples/blink` | process tests |
| 10 | Determinism | compile twice → byte-identical |
| 11 | `arduino-cli compile --fqbn arduino:avr:uno` check | loud skip-with-reason if toolchain missing |
| 12 | `SUBSET.md`, `DIAGNOSTICS.md`, Wokwi instructions | — |

## Extension hooks honoured (PRD §9.10)
- IR is the only input to the emitter; the emitter never sees the AST.
- Board decisions sit behind `Target` (one impl: `UnoTarget`).
- All codes/messages live in one registry.
- Dart → C++ call mapping is a data table (`ApiRegistry`).
- Validator is a list of independent rules; Phase 2 relaxes them one at a time.
