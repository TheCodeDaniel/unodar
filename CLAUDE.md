# CLAUDE.md — working agreement for this repo

Read `docs/PRD.md` (scope, source of truth) and `docs/PLAN.md` (current phase plan) before writing code.

## Ground rules
- **Build only the current phase** (see PRD §8). Later phases are design context, never early work.
- **Test first.** Every compiler feature starts as a golden test (`packages/unodar_compiler/test/golden/<case>/`).
- **Reject loudly, never miscompile.** Unsupported Dart gets a diagnostic (code, location, suggestion).
- **Ambiguity:** pick the simpler option and log it in `docs/DECISIONS.md`. For PRD §13 open decisions, stop and ask.
- **Toolchain missing?** Fail loudly with install instructions. Never skip verification silently.
- `packages/unodar` must never depend on `analyzer` or Flutter.
- **Size budgets** (`packages/unodar_compiler/test/size_budgets.dart`) change only in a dedicated commit that explains
  why the output grew and shows the new measurement. Never bump a budget to get a red test green.
- **Git history:** never rewrite history (rebase, amend, reset, squash of existing commits) or force-push without
  asking the maintainer first.

## Style
- Line length is **120** everywhere (set once in the root `analysis_options.yaml`, inherited by all packages).
- Small commits with detailed messages: what, why, design trade-offs, how it was verified.

## Commands (run from repo root)
```sh
dart pub get
dart analyze && dart format --set-exit-if-changed . && dart test packages/unodar packages/unodar_compiler
UPDATE_GOLDENS=1 dart test packages/unodar_compiler/test/golden_test.dart   # deliberately rewrite goldens
dart run packages/unodar_compiler/bin/unodar.dart build examples/blink/main.dart -o out
tool/check_arduino.sh                                                     # arduino-cli compile of the examples
tool/extract_arduino_names.sh                                             # regenerate input for the E014 deny-list
```
Tests tagged `arduino` (compile checks, size budgets, fidelity harnesses, reserved names) skip with install
instructions when arduino-cli is missing. **CI must set `UNODAR_REQUIRE_ARDUINO=1`** so they fail instead.

## Pipeline map (`packages/unodar_compiler/lib/src/`)
`frontend/` (analyzer, resolved AST) → `validator/` (subset rules + lowering to IR) → `ir/` → `emitter/`
(IR → C++ via a `Target`) → `cli/`. Diagnostics live in one registry: `diagnostics/codes.dart`.
