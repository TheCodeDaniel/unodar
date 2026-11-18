# Unodar

> **Experimental.** Flutter that compiles to Arduino.

Unodar lets Dart developers program an Arduino Uno. You write Flutter-style Dart (widgets, named parameters,
signals); the unodar compiler turns it into plain, heap-free Arduino C++ and uploads it to the board. It is its own
framework, written in Dart, with **no** dependency on the Flutter SDK.

```dart
import 'package:unodar/unodar.dart';

final led = Led(pin: LED_BUILTIN);
final button = Button(pin: 2, onPressed: () { led.toggle(); });

void main() => runDevice(Device(board: Uno(), children: [led, button]));
```

## Quick start

You need the [Dart SDK](https://dart.dev/get-dart) 3.13 or later (the one inside Flutter works too: check with
`dart --version`), an Arduino Uno (or a clone) and a USB cable that carries data. macOS and Linux are supported;
**Windows is untested in v0.7**.

<!-- quickstart -->
```sh
dart pub global activate --source git https://github.com/TheCodeDaniel/unodar \
  --git-path packages/unodar_compiler --git-ref v0.7.0
unodar setup
unodar new hello
cd hello
unodar flash
```
<!-- /quickstart -->

1. The first line installs the `unodar` command. If your shell then says `unodar: command not found`, add pub's
   folder to your `PATH` as the line's own output says (usually `export PATH="$PATH":"$HOME/.pub-cache/bin"`).
2. `unodar setup` downloads the Arduino toolchain unodar is tested with (arduino-cli, the AVR compiler and four
   libraries, about 450 MB, 1–3 minutes) into `~/.unodar`. Nothing else on your system changes.
3. `unodar new hello` creates a project whose `main.dart` blinks the LED on the board. Nothing to wire.
4. `unodar flash` builds it and uploads it to the Uno plugged in. Success looks like:

   ```text
   build/main/main.ino
   flash 940 B of 32256 (2 %), RAM 19 B of 2048 (0 %)
   Uploading to /dev/cu.usbmodem1101...
   Done: the program is running on the board.
   ```

   and the LED marked **L** blinks once a second.

Something different? Run `unodar doctor`: it checks everything and prints the command that fixes each problem.
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) covers the rest.

## Next

- [`docs/FIRST_PROGRAM.md`](docs/FIRST_PROGRAM.md): from the blinking LED to a button that toggles it, and how to
  read an error.
- [`docs/INSTALL.md`](docs/INSTALL.md): what gets installed where, proxies, updating and uninstalling.
- [`docs/SUBSET.md`](docs/SUBSET.md): exactly which Dart unodar accepts, every widget and library.
- [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md): every error code (E001–E028), with examples.
- [`docs/STATUS.md`](docs/STATUS.md): what works today, and the known limits.
- [`examples/`](examples): `blink`, `pulse`, `dial` (a potentiometer turns a servo), `button_led`, `counter`, and
  `thermostat` (a DHT22, a 16×2 LCD and the setpoint kept in EEPROM); several run in Wokwi (their `wokwi/` folders).

## Commands

| Command | What it does |
|---|---|
| `unodar new <name>` | Create a project folder with a `main.dart` that blinks the board LED. |
| `unodar build [file]` | Compile `main.dart` (or `file`) to C++ in `build/`, build it for the Uno, print its flash and RAM use. `--cpp-only` writes only the C++. |
| `unodar flash [file] [--port P]` | Build, then upload to the one Uno plugged in (or to port `P`). |
| `unodar setup [--dev]` | Install the tested toolchain into `~/.unodar`; safe to re-run. |
| `unodar doctor [--dev]` | Check the toolchain, the project and the board, with the fix for each problem. |

Exit codes: 0 success, 1 a problem in your Dart, 2 usage or a unodar bug, 3 the toolchain, 4 the board
(see [`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md#exit-codes)).

## Contributing

```sh
git clone https://github.com/TheCodeDaniel/unodar && cd unodar
dart pub get
dart run unodar_compiler:unodar setup --dev     # also needs Node.js 20.19+, for the simulator tests
dart analyze && dart format --set-exit-if-changed . && dart test packages/unodar packages/unodar_compiler
```

Read `CLAUDE.md` (the working rules), [`docs/PRD.md`](docs/PRD.md) and [`docs/PLAN.md`](docs/PLAN.md) first.

| Path | What |
|---|---|
| `packages/unodar` | User-facing API. Declarations only (for autocomplete and `dart analyze`); never executed. |
| `packages/unodar_compiler` | Analyzer-based compiler and the `unodar` CLI. |
| `runtime/` | `unodar_widgets.h`, the hand-written widget and signal runtime that widget programs include, and `unodar_spi.h`, the SPI shim (both embedded in the compiler). |
| `examples/` | Example programs written in Dart, each with notes for running it. |
| `tool/` | `check_arduino.sh` (builds every example), the E014 name extractor, `embed_runtime.sh` (embeds the runtime headers and the toolchain manifests in the compiler), `arduino_toolchain.txt` and `arduino_libraries.txt` (the pinned toolchain), `fresh_machine_test.sh` (the README quick start on a clean account), and `avr_runner/` (avr8js simulator with pin I/O and models of EEPROM, an SPI slave, an HD44780 LCD and a DHT22, for the runtime tests). |
| `docs/` | PRD, plan, subset spec, diagnostics reference, decisions log, and the user guides above. |

## License
MIT
