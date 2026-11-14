# Unodar — Product Requirements Document (PRD)

**Version:** 0.1 (pre-implementation)  
**Owner:** Daniel Ainoko  
**Status:** Active. Phase 1 (tagged v0.1.0), Phase 2 (language core, tagged v0.2.0) and Phase 3 (hardware + interop foundation, tagged v0.3.0) and Phase 4 (static widget tree, tagged v0.4.0) are done; Phase 5 (signals) is in progress on the `phase-5` branch.  
**Audience:** The maintainer and Claude Code (as the implementing engineer). Read this fully before writing code.

---

## 0. How to use this document (read first)

1. This PRD describes the **whole product** so you understand where the code is heading, and specifies **Phase 1 in detail** so you know exactly what to build now.
2. **Build only the current phase.** Later phases are context. Never implement them early. But design Phase 1 so later phases fit without rewrites (see §9.4, "Extension hooks").
3. When something is ambiguous: choose the simpler option, record the decision in `docs/DECISIONS.md` (date, decision, reason), and mention it in your report. For items in §13 ("Open decisions") **stop and ask** instead of deciding.
4. This doc is the source of truth for scope. If a request conflicts with the non-goals (§3), say so and ask before proceeding.

---

## 1. Summary

**Unodar** is an experimental framework that lets Flutter and Dart developers program Arduino-class microcontrollers using Flutter-style declarative Dart. A compiler reads a strict subset of Dart and emits plain, readable, heap-free Arduino C++, which the standard `arduino-cli` toolchain builds and flashes.

**Pitch:** *Flutter that compiles to Arduino.*

Unodar is its **own framework**. It is written in the Dart language, but it does **not** depend on the Flutter SDK. "Flutter-like" describes the API feel (declarative trees, named parameters, reactive state), not the implementation.

---

## 2. Problem and opportunity

- Flutter/Dart developers are a large group who think in widgets and state. Almost none of them do embedded work, because the barrier is C++ and a very different mental model.
- Existing options each give up something: C++ (steep learning curve), MicroPython (different language, runtime cost), Toit (new language + VM). There is no mature "write Flutter-style Dart, run it on a microcontroller" path.
- The Arduino ecosystem has thousands of libraries and boards. A new framework is only valuable if developers can still reach that ecosystem from day one.
- Many developers want to build things they feel they *own*, with a physical result. Hardware gives that.

**Opportunity:** be the easiest way for a Dart developer to make something blink, sense, and move, without learning C++.

---

## 3. Goals and non-goals

### Goals
- G1. A Dart developer with no C++ knowledge can go from zero to a blinking Uno in under 10 minutes.
- G2. Declarative, Flutter-feeling API: widgets, named params, reactive state.
- G3. Full access to the Arduino library ecosystem through simple interop (writable in ~10 lines per library, plus an escape hatch).
- G4. Generated code is small, readable, traceable to Dart source, and uses **no heap** on AVR.
- G5. Great diagnostics: unsupported Dart is rejected with a clear error and a suggestion.
- G6. Everything verifiable without hardware wherever possible (golden tests, `arduino-cli` compile, simulator).

### Non-goals (do not build, do not "helpfully" add)
- NG1. **Not a general Dart compiler.** We support a small strict subset. The limit exists because full Dart assumes a runtime (GC, async/event loop, reified generics, `dynamic`) that cannot fit in 2 KB of RAM, not because parsing is hard.
- NG2. **Not built on the Flutter SDK.** No `package:flutter`, no `dart:ui`.
- NG3. No Flutter-style runtime: no widget diffing, no element tree, no `setState`, no hot reload on device. (Fast compile + flash is the substitute.)
- NG4. No `dynamic`, reflection, isolates, `async`/`await`/`Future`/`Stream`, exceptions, or `dart:io`.
- NG5. No dynamic memory in generated code targeting AVR.
- NG6. Not trying to replace C++ for experts or compete on performance.
- NG7. No monetization, hosted services, or accounts. This is an open-source project.

---

## 4. Users

**Primary: the Flutter developer.** Knows Dart, widgets, Riverpod-style state. Has maybe built an Arduino tutorial once and bounced off C++. Wants to build a physical project (sensor dashboard, robot, smart gadget) using skills they already have.

**Secondary: the Dart-curious hobbyist or student** getting into electronics who finds Dart friendlier than C++.

**Maintainer persona (internal):** a busy solo developer building in spare time with Claude Code. Priorities: small steps, always-green tests, nothing that rots.

---

## 5. Product principles

1. **Dumb and flat beats clever.** If a feature needs a heap or a runtime, it is out of the subset.
2. **The framework dictates the shapes.** Users write widgets, not arbitrary programs. That keeps the compiler small.
3. **Reject loudly, never miscompile.** Every unsupported construct gets a diagnostic with code, location, and suggestion.
4. **The Dart API is the product.** Autocomplete, `dart analyze`, and docs work because the framework is real Dart (declarations); the real implementation lives in C++ headers.
5. **Traceable output.** Generated C++ carries `#line` directives so C++ compiler errors point at Dart lines.
6. **Test first.** Every feature begins as a golden test (Dart input + expected C++ output).
7. **Honest docs.** `SUBSET.md` states exactly what works. Mark the project experimental until 1.0.

---

## 6. Target hardware

| Resource | Arduino Uno (ATmega328P) — first target | ESP32 — later |
|---|---|---|
| SRAM | 2 KB | ~320 KB |
| Flash | 32 KB | 4 MB+ |
| Clock | 16 MHz | 160–240 MHz |
| Native `int` | 16-bit | 32-bit |
| `double` | same as `float` (4 bytes) | `float` 4 B / `double` 8 B |

Consequences: no heap in generated code on AVR; string literals stored in flash via `F("...")`; flash/RAM size budgets enforced in CI.

---

## 7. Product vision (how it will feel at 1.0)

```dart
import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

void main() => runDevice(
  Device(
    board: Uno(),
    children: [
      Button(pin: 2, onPressed: () => count.value++),
      Led(pin: 13, on: count.isOdd),
      Every(Duration(milliseconds: 500), () => Serial.println('tick')),
      Oled(child: Column([Text('Count'), Text('${count.value}')])),
    ],
  ),
);
```

CLI: `unodar build`, `unodar flash --port ...`, `unodar run`, `unodar doctor`.

Interop (compile-time bindings, not runtime FFI):

```dart
@CppHeader('Adafruit_BMP280.h')
@CppClass('Adafruit_BMP280')
class Bmp280 {
  external Bmp280();
  external bool begin(int address);
  external double readTemperature();
}
```

Escape hatch for anything not yet wrapped: a raw `cpp('...')` call and `@CppInclude('Foo.h')`.

Later: ESP32 support with WiFi/BLE widgets, OTA flashing, and a separate Flutter phone app that talks to the board (Flutter is a *consumer* there, never a dependency).

---

## 8. Roadmap to 1.0 (11 phases)

Each phase has an exit gate. Do not start a phase until the previous gate passes.

| # | Phase | Scope | Version |
|---|---|---|---|
| 0 | Setup | Repo, license, tooling, `CLAUDE.md`, Wokwi project | — |
| **1** | **Walking skeleton** | **Dart `setup()`/`loop()` → blink `.ino`; analyzer frontend; diagnostics; golden harness; `#line`; CLI `build`** | **0.1** |
| 2 | Language core (**done**, tagged v0.2.0) | ints, bools, doubles, consts, top-level vars, arithmetic/logic, `if`/`while`/`for`, functions, sized ints (`Uint8`...), rejection diagnostics | 0.2 |
| 3 | Hardware + interop foundation (**done**, tagged v0.3.0) | `Serial`, analog I/O, flash strings, `@CppClass`/`@CppHeader`, `cpp()` escape hatch, `Servo` + `Wire` bindings | 0.3 |
| 4 | Static widget tree (**done**, tagged v0.4.0) | `runDevice`, `Device`, `Led`, `Button` (debounced), `Every`; non-capturing closures → generated functions | 0.4 |
| 5 | Signals (in progress) | `Signal<T>` (value + dirty flag), `Watch`, restricted `Computed`, binding to widgets (`Led(on:)`), no heap | 0.5 |
| 6 | Classes + library wrappers | Simple classes → structs; first-party wrappers for top ~10 libs (SPI, LiquidCrystal, DHT, SSD1306, NeoPixel...) | 0.6 |
| 7 | CLI and DX | `flash`, `run`, `doctor`, `setup` (toolchain bootstrap, §8.1), friendly errors, 10-minute quickstart | 0.7 (**public announce**) |
| 8 | Display widgets | `Oled` + `Column`/`Row`/`Text`/`Padding`, layout resolved at compile time | 0.8 |
| 9 | ESP32 target | Board abstraction, WiFi/BLE, OTA, phone-to-board demo | 0.9 |
| 10 | Hardening + docs | Frozen `SUBSET.md`, semver'd API, docs site, full CI, early-user fixes | **1.0** |

**Announce bar (after Phase 7):** one Dart file builds and flashes; a button toggles an LED on a real Uno; a 60-second demo exists; `SUBSET.md` is honest; labeled experimental.

**1.0 definition:** stable subset spec, semver'd public API, Uno + ESP32 supported, ≥10 first-party library wrappers, docs site, green CI, and fixes driven by real early users. Do not tag 1.0 until real users have run 0.5+ for a while.

### 8.1 Phase 7 requirement: toolchain bootstrap

Design context for Phase 7; do not build it earlier.

- `unodar setup` downloads a **managed** copy of `arduino-cli` and the cores the supported boards need (today
  `arduino:avr`) into `~/.unodar`. It pins the versions unodar is tested against, is safe to re-run, and never
  modifies a system-wide Arduino installation.
- `unodar doctor` checks the managed toolchain (present, expected versions, cores installed) and also reports any
  `arduino-cli` found on `PATH`. Every problem it finds comes with the exact command that fixes it.
- `unodar build` and `unodar flash` use the managed copy in `~/.unodar` first and fall back to `arduino-cli` on
  `PATH`. If neither is usable, they fail loudly and tell the user to run `unodar setup`.

---

## 9. Phase 1 specification (CURRENT BUILD TARGET)

### 9.1 Objective
Prove the full pipeline end-to-end on the smallest possible slice: a Dart file with `setup()` and `loop()` is compiled to a valid `.ino` that builds for the Uno, and every unsupported construct is rejected with a good diagnostic.

### 9.2 Input contract (what the user writes)

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(13, HIGH);
  delay(500);
  digitalWrite(13, LOW);
  delay(500);
}
```

Phase 1 supported subset:
- Imports: only `package:unodar/unodar.dart`.
- Top-level functions `void setup()` and `void loop()` (no parameters, `void` return). Both required.
- Statements: expression statements that are calls to the unodar API functions `pinMode`, `digitalWrite`, `delay`.
- Arguments: integer literals, and the unodar constants `HIGH`, `LOW`, `OUTPUT`, `INPUT`, `INPUT_PULLUP`.
- Comments are allowed and ignored.

`main()` is **reserved** for the Phase 4 widget API. If present in Phase 1, report a diagnostic explaining it is reserved (do not compile it).

Everything else is **out of scope in Phase 1** (and must produce a diagnostic): variables, classes, other statements (`if`, loops, `return` values), other function declarations, expressions beyond a single call, string literals, any non-allow-listed call.

### 9.3 Output contract (what the compiler emits)

A single `<name>.ino` in `<outdir>/<name>/`. Indicative shape (the reviewed golden file is authoritative; keep it readable and stable):

```cpp
#include <Arduino.h>

#line 3 "blink.dart"
void setup() {
#line 4 "blink.dart"
  pinMode(13, OUTPUT);
}

#line 7 "blink.dart"
void loop() {
#line 8 "blink.dart"
  digitalWrite(13, HIGH);
#line 9 "blink.dart"
  delay(500);
#line 10 "blink.dart"
  digitalWrite(13, LOW);
#line 11 "blink.dart"
  delay(500);
}
```

Requirements: deterministic output (same input → byte-identical output); consistent formatting; `#line` before each emitted statement/function; no heap use; trailing newline.

### 9.4 Packages and layout

Use a Dart pub workspace (Dart ≥ 3.6; verify with `dart --version` and tell the maintainer if the SDK is older).

```
unodar/
  pubspec.yaml                  # workspace root
  README.md  LICENSE(MIT)  CLAUDE.md
  docs/ PLAN.md PRD.md SUBSET.md DIAGNOSTICS.md DECISIONS.md
  packages/
    unodar/                     # user-facing API: declarations only, NO analyzer dep
      lib/unodar.dart
      lib/src/arduino_core.dart # pinMode, digitalWrite, delay, HIGH/LOW/OUTPUT/INPUT/INPUT_PULLUP
    unodar_compiler/            # analyzer + CLI
      bin/unodar.dart
      lib/src/{frontend,validator,ir,emitter,diagnostics,cli}/
      test/{golden,unit}/
  runtime/                      # C++ headers (empty or placeholder in Phase 1)
  examples/blink/main.dart
```

API declarations in `packages/unodar` are real Dart functions/constants (bodies may be `throw UnimplementedError()` or `external`) so users get autocomplete and `dart analyze`. They are **never executed**; they exist for the analyzer.

### 9.5 Pipeline

1. **Frontend:** resolve the input file with `package:analyzer` (fully resolved AST). Surface analyzer errors in the user's file as diagnostics (E007).
2. **Validator:** enforce the Phase 1 subset; collect *all* diagnostics (don't stop at the first).
3. **IR:** lower to a small intermediate representation (functions → statements → API calls with constant args). Keep it tiny but real; later phases extend it.
4. **Emitter:** IR → C++ text with `#line` directives.
5. **Toolchain (external):** `arduino-cli compile` verifies the output (used by tests and manually).

### 9.6 Diagnostics (E-codes)

Each diagnostic has: code, severity, `file:line:col`, message, and a short suggestion. Format: `blink.dart:5:3: error[E003]: unknown function 'tone'. Only pinMode, digitalWrite, and delay are supported in this version.`

| Code | Meaning |
|---|---|
| E001 | Missing required `setup()` or `loop()` |
| E002 | Unsupported statement or expression kind |
| E003 | Call to a function that is not part of the supported unodar API |
| E004 | Unsupported argument (only int literals and unodar constants allowed) |
| E005 | Unsupported top-level declaration (variables, classes, extra functions) |
| E006 | Invalid `setup`/`loop` signature (must be `void`, no parameters) |
| E007 | Dart analysis error in the source file (type error, syntax error, unresolved import) |
| E008 | `main()` is reserved (widget API arrives in a later phase) |

Document every code in `docs/DIAGNOSTICS.md` with an example. Exit codes: 0 success; 1 diagnostics (user error); 2 internal/tooling error.

### 9.7 CLI

`dart run packages/unodar_compiler/bin/unodar.dart build <file.dart> -o <outdir>`
- Writes `<outdir>/<name>/<name>.ino` where `<name>` is the Dart file's base name.
- Prints diagnostics to stderr; prints the output path on success.
- `--help` documents usage. No other commands in Phase 1.

### 9.8 Testing requirements

- **Golden tests** under `packages/unodar_compiler/test/golden/<case>/` with `input.dart` and `expected.ino` (or `expected_errors.txt` for failures). A flag/env var updates goldens deliberately.
- Required positive case: `blink`.
- Required negative cases (at least): missing `loop` (E001), unsupported statement such as an `if` (E002), unknown function (E003), non-literal argument (E004), top-level variable (E005), bad signature (E006), type error in source (E007), `main()` present (E008).
- Determinism test: compile twice, outputs identical.
- **Compile check:** a test (or script) that runs `arduino-cli compile --fqbn arduino:avr:uno` on the generated blink sketch. If `arduino-cli` or the `arduino:avr` core is missing, tell the maintainer exactly what to install and **do not silently skip** (mark the test clearly as skipped-with-reason and report it).
- Before finishing: `dart analyze && dart format --set-exit-if-changed . && dart test` must pass.

### 9.9 Acceptance criteria (Phase 1 is done when ALL are true)

1. The blink golden test passes and the generated sketch compiles for `arduino:avr:uno`.
2. All required negative cases produce the specified E-codes with correct locations and suggestions.
3. Output is deterministic and carries `#line` directives that map back to the Dart source.
4. `docs/SUBSET.md` and `docs/DIAGNOSTICS.md` accurately describe exactly what Phase 1 supports and rejects.
5. `packages/unodar` has no dependency on `analyzer` or Flutter.
6. Analyzer, formatter, and tests are green.
7. The maintainer can paste the generated sketch into Wokwi (or flash a real Uno) and see the LED blink.

### 9.10 Extension hooks (design for later phases, do not implement them)

- **IR is the seam.** Later phases add expression nodes, variables, widgets, and signals. Do not emit C++ directly from the AST.
- **Emitter is target-aware by construction:** keep board-specific decisions (type widths, includes) behind a small `Target` interface with one implementation (`UnoTarget`). ESP32 arrives in Phase 9.
- **Diagnostics are centralized** (one registry of codes/messages) so new phases just add entries.
- **The API-call table** (which Dart functions map to which C++ calls) should be data-driven (a registry), because Phase 3 adds many more calls and interop bindings.
- **Validator rules are composable** so Phase 2 can relax them construct by construct.

### 9.11 Explicitly out of scope for Phase 1

Variables, expressions, control flow, strings, `Serial`, widgets, `Signal`, classes, C++ interop annotations, `flash`/`run`/`doctor` commands, ESP32, display work, simulators in CI, and performance tuning. If you notice you are building any of these, stop.

---

## 10. Architecture overview (whole product)

```
 app.dart ──► Frontend (analyzer, resolved AST)
          ──► Validator (subset + diagnostics)
          ──► Lowering (widgets/closures/signals → IR)
          ──► Emitter (IR → C++ with #line)
          ──► arduino-cli (compile / upload)
```

Key long-term decisions (already made — do not relitigate without asking):
- Analyzer-based frontend (not `package:kernel`).
- The widget tree is **read statically, never executed**. The compiler pattern-matches known widget constructors.
- Closures compile to plain generated functions; they may only reference top-level state (no captured locals).
- Signals are C++ templates (value + dirty flag); the generated `loop()` polls inputs, ticks timers, flushes dirty signals.
- Interop is compile-time (`@CppClass` etc.), not runtime FFI.
- Dart `int` maps to `int32_t` on every target (decided in Phase 2; see §13 and `docs/DECISIONS.md`).

---

## 11. Quality bar and metrics

- G1 benchmark: fresh clone → blinking Uno in < 10 minutes (measured at Phase 7).
- Blink example size budget on Uno (set after Phase 1 measurement, then enforced in CI).
- Zero `new`/`malloc`/`String(` in generated AVR output (enforced from Phase 3 on).
- Every supported construct has a positive golden test; every rejected construct has a negative golden test.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| Scope creep toward a "real Dart compiler" | Non-goals; `SUBSET.md` updated before any syntax is added; golden test first |
| Dart vs C++ numeric semantics (64-bit `int` vs 16-bit AVR) | Document mapping; sized int types in Phase 2; overflow tests |
| 2 KB RAM exhausted | Size budgets in CI; no-heap rule; flash strings |
| Hard-to-debug generated C++ | `#line` directives; `--verbose` dump later; readable emitter |
| Library bindings never end | Hand-write what is used; escape hatch; defer a generator |
| Solo-maintainer burnout | Small phases; always-green tests; announce only after Phase 7 |
| Toolchain missing on dev machine | Fail loudly with install instructions; never skip silently |

---

## 13. Open decisions (STOP AND ASK before deciding)

1. ~~Dart `int` mapping~~ **Decided (Phase 2):** `int` → `int32_t` everywhere, `double` → `float`, plus sized `Uint8`/`Uint16`/`Int16`. See `docs/DECISIONS.md`.
2. ~~Output as single `.ino` vs `.cpp` + `.h`~~ **Decided (Phase 4):** the generated program stays one `.ino`; a program that uses widgets also gets a copy of the fixed, hand-written runtime header `unodar_widgets.h` in the same sketch folder. See `docs/DECISIONS.md`.
3. ~~Computed/derived signals~~ **Decided (Phase 5):** restricted expressions. A `Computed` is a single `=>` expression over signals and Computeds declared above it and constants, no calls; general closures may come later. See `docs/DECISIONS.md`.
4. Fixed-size list design (e.g. `FixedList<int, 8>`) (not before Phase 6).
5. Board abstraction shape before ESP32 (Phase 9).
6. Whether to build a C++ header binding generator (after hand-written bindings prove painful).

---

## 14. Glossary

- **Subset:** the restricted slice of Dart the compiler accepts.
- **Golden test:** a test comparing compiler output to a reviewed, committed expected file.
- **Walking skeleton:** the thinnest end-to-end slice through every pipeline stage.
- **IR:** the compiler's intermediate representation between analyzer AST and C++ text.
- **Escape hatch:** `cpp('...')` / `@CppInclude`, allowing raw C++ for anything not yet wrapped.
- **Wokwi:** online/VS Code Arduino simulator used for hardware-free behavior checks.
- **`arduino-cli`:** Arduino's command-line build/upload tool, used as the external compile step.
