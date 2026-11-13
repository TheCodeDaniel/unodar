# Unodar

> **Experimental.** Flutter that compiles to Arduino.

Unodar lets Dart developers program Arduino-class microcontrollers. A compiler reads a strict subset of Dart and
emits plain, readable, heap-free Arduino C++, which the standard `arduino-cli` toolchain builds and flashes.
It is its own framework: written in Dart, with **no** dependency on the Flutter SDK.

## Status
Phase 3 (hardware API and interop foundation, v0.3) is done, on top of the Phase 2 language core (`int`/`double`/
`bool`, sized `Uint8`/`Uint16`/`Int16`, variables, Dart-faithful arithmetic, `if`/`while`/`for`, your own functions):

- **Hardware API:** `pinMode`, `digitalWrite`, `digitalRead`, `analogRead`, `analogWrite`, `delay`, `millis`,
  `micros`, `A0`–`A5`, `LED_BUILTIN`, with 32-bit `int` results on the 16-bit Uno.
- **Serial:** `Serial.begin/print/println` of string literals (stored in flash with `F()`), ints, doubles
  (`digits:`), and bools.
- **Interop:** bind existing C++ classes with `@CppClass`, `@CppHeader`, `@CppName`, `@CppType`, `@CppRange`.
  Bindings ship for **Wire** and **Servo**. Raw C++ goes through `cpp('…')` and `@CppInclude`.
- **No heap:** checked on every linked program.

Examples: [`examples/blink`](examples/blink), [`examples/pulse`](examples/pulse), and
[`examples/dial`](examples/dial) (a potentiometer turns a servo and readings go to the serial monitor; runs in Wokwi,
see [`examples/dial/wokwi`](examples/dial/wokwi)). See [`docs/SUBSET.md`](docs/SUBSET.md) for exactly what is
accepted and [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md) for every error code (E001–E020). The roadmap is in
[`docs/PRD.md`](docs/PRD.md); Phase 4 (widgets) is next.

## Known limits
Unodar is experimental. Beyond the subset itself (`docs/SUBSET.md`), these are the limits to know about:

- **Arduino Uno only**, and the CLI only builds (`unodar build`): you compile and flash with `arduino-cli` yourself,
  with the `-fwrapv` build properties below. `flash`, `run`, and toolchain setup arrive in Phase 7.
- **Runtime behaviour that differs from Dart** is listed in "Known deviations from Dart" in `docs/SUBSET.md`:
  - `int` overflow wraps at 32 bits, and `double` is a 32-bit `float`;
  - integer division by a zero variable is undefined;
  - `millis()` wraps after about 24.8 days, so compare elapsed time (`now - last >= interval`), not readings;
  - `Serial.print` of a double uses Arduino's format.
- **Two calls in one expression are rejected** (E013), e.g. `Wire.read() * 256 + Wire.read()`, because C++ may
  run them in either order. Store each result in a local first.
- **Only constant arguments are range-checked** (E004, including `@CppRange` limits such as Servo's pulse widths).
  Runtime values are converted by C++ rules.
- **Strings exist only as `Serial.print` literals**: no `String` variables, interpolation, or string arguments to
  your own functions.
- **Objects exist only through bindings**, as top-level `final` objects or `external final` existing ones: no
  classes of your own yet (Phase 6), and no binding objects as locals, parameters, or results.
- **Libraries reserve RAM** before your code runs, out of 2048 B. Measured: Serial about 200 B, Wire about 200 B
  more, Servo about 50 B. arduino-cli reports the total as "Global variables use …".
- **`cpp('…')` is not checked**, except that heap words are rejected (E020). What it does is up to you.
- **Wokwi on wokwi.com builds without `-fwrapv`.** The examples never overflow, so they behave the same there; Wokwi
  for VS Code runs the firmware you build with the flags.
- **Requirements:** arduino-cli with `arduino:avr` 1.8.8 and `Servo` 1.3.0 for builds, and Node.js 20.19+ for the
  runtime tests (`(cd tool/avr_runner && npm ci)`). Tests that need them skip with install instructions; CI
  requires them.

## Quick start
```sh
dart pub get
dart run packages/unodar_compiler/bin/unodar.dart build examples/blink/main.dart -o out
# -> out/main/main.ino; compile it with:
arduino-cli compile --fqbn arduino:avr:uno --build-property compiler.c.extra_flags=-fwrapv \
  --build-property compiler.cpp.extra_flags=-fwrapv --build-property compiler.c.elf.extra_flags=-fwrapv out/main
```

## Layout
| Path | What |
|---|---|
| `packages/unodar` | User-facing API. Declarations only (for autocomplete and `dart analyze`); never executed. |
| `packages/unodar_compiler` | Analyzer-based compiler and the `unodar` CLI. |
| `runtime/` | C++ headers for later phases (empty so far). |
| `examples/` | Example sketches written in Dart (`blink`, `pulse`, `dial`, each with notes for running it). |
| `tool/` | `check_arduino.sh` (builds the examples with arduino-cli), the E014 name extractor, and `avr_runner/` (avr8js simulator for the runtime tests). |
| `docs/` | PRD, plan, subset spec, diagnostics reference, decisions log. |

## License
MIT
