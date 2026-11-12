# Unodar

> **Experimental.** Flutter that compiles to Arduino.

Unodar lets Dart developers program Arduino-class microcontrollers. A compiler reads a strict subset of Dart and
emits plain, readable, heap-free Arduino C++, which the standard `arduino-cli` toolchain builds and flashes.
It is its own framework: written in Dart, with **no** dependency on the Flutter SDK.

## Status
Phase 2 (language core): `int`/`double`/`bool` and sized `Uint8`/`Uint16`/`Int16`, top-level and local variables,
arithmetic/comparison/logical expressions with Dart semantics, `if`/`while`/`for`, and your own functions, calling
`pinMode`, `digitalWrite`, `delay`. Examples: [`examples/blink`](examples/blink), [`examples/pulse`](examples/pulse).
See
[`docs/SUBSET.md`](docs/SUBSET.md) for exactly what is accepted and [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md)
for every error code. The roadmap is in [`docs/PRD.md`](docs/PRD.md).

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
| `runtime/` | C++ headers for later phases (empty in Phase 1). |
| `examples/` | Example sketches written in Dart. |
| `docs/` | PRD, plan, subset spec, diagnostics reference, decisions log. |

## License
MIT
