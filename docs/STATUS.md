# Status and known limits

## What works today

- **Phase 7 (v0.7), the command line:** `unodar new`, `build` (compiles with arduino-cli and prints flash and RAM
  use), `flash` (finds the one Uno plugged in), `setup` (installs the tested toolchain into `~/.unodar`) and `doctor`
  (checks it, with the fix for each problem); diagnostics show the line you wrote and link to their documentation;
  common first attempts from Flutter (`print`, `setState`, `async main`, `StatelessWidget`, a Flutter import) say
  what to write instead.
- **Phase 6 (v0.6), classes and library wrappers:** organise a program into your own classes and enums, and use
  EEPROM, SPI, SoftwareSerial, LiquidCrystal and DHT sensors. No heap, no vtables, no objects copied.

```dart
enum Mode { idle, heating }

class Thermostat {
  final int hysteresis;
  Mode mode = Mode.idle;

  Thermostat({this.hysteresis = 1});

  void update(double temperature, int target) {
    if (mode == Mode.idle && temperature < target - hysteresis) {
      mode = Mode.heating;
    } else if (mode == Mode.heating && temperature > target + hysteresis) {
      mode = Mode.idle;
    }
  }

  bool get heating => mode == Mode.heating;
}

final thermostat = Thermostat(hysteresis: 1);
final sensor = Dht(8, DHT22);
final lcd = LiquidCrystal(12, 11, 5, 4, 3, 2);
```

- **Classes:** fields, one constructor without a body (named parameters, initializing formals, an initializer
  list), methods, getters, static members, and composition (a `final` field holding another object, created in
  place). An object is a top-level `final` or such a field, used only through its fields and methods; it becomes a
  C++ `struct` global, constant-initialized. No inheritance, interfaces, mixins, operators or setters (E027), and
  objects are never passed, stored or compared (E018).
- **Enums and `switch`:** simple enums (`enum class : uint8_t`, `.index`, `Signal<Mode>`); `switch` statements on
  ints and enums with constant cases, Dart 3 semantics (no fall-through).
- **`OnStart(() { … })`:** a widget that runs once in `setup()`, at its place in `children`, for library setup.
- **Library wrappers,** each imported on its own (`import 'package:unodar/eeprom.dart';`): EEPROM, SPI,
  SoftwareSerial, LiquidCrystal (parallel HD44780 LCDs) and DHT (DHT11/DHT22). Each is checked against its C++
  header by a conformance probe, and each SUBSET section says what is verified in the simulator and what only on a
  real board. Pins are checked across widgets and bindings (`@CppPin`, `@CppUsesPins`).
- **Phase 5 (v0.5), signals:** `Signal<T>`, `Computed`, `Watch`, and a `Led` that follows a signal.
- **Signals (Phase 5):** `Signal<T>` (`int`, `double`, `bool`, `Uint8`, `Uint16`, `Int16`) read and written through `.value`;
  `Watch(signal, (v) { … })`; `Computed(() => …)`, a single expression over signals declared above; `Led(on: …)`
  and `led.set(b)`. A write only marks the signal; at the end of every `loop()` pass, one generated function delivers
  each change once, in declaration order (a write made by a Watch arrives in the next pass). Equal writes deliver
  nothing; initial values are delivered once at the end of `setup()`. Cycles are compile errors (E025).
- **Phase 4 (v0.4), widgets:** `runDevice(Device(board: Uno(), children: [...]))` with `Led`
  (`on`/`off`/`toggle`), `Button` (internal pull-up, 50 ms debounce, `onPressed` once per press) and
  `Every(Duration(…), () { … })` (drift-free, safe across the `millis()` wrap). The tree is read at compile time
  and becomes flat C++: one static object per widget, a plain function per callback, and a generated
  `setup()`/`loop()`. The runtime is one fixed header, `runtime/unodar_widgets.h`, which `unodar build` writes next
  to the `.ino`.
- **Phase 3 (v0.3), hardware and interop:** `pinMode`, `digitalWrite`, `digitalRead`, `analogRead`,
  `analogWrite`, `delay`, `millis`, `micros`, `A0`–`A5`, `LED_BUILTIN`; `Serial` (flash-string literals, ints,
  doubles with `digits:`, bools); bindings for existing C++ classes (`@CppClass`, …) with **Wire** and **Servo**
  shipped; raw C++ through `cpp('…')` and `@CppInclude`.
- **Phase 2 (v0.2), language core:** `int`/`double`/`bool`, sized `Uint8`/`Uint16`/`Int16`, variables,
  Dart-faithful arithmetic, `if`/`while`/`for`, your own functions.
- **No heap:** checked on every linked program.

## Known limits
Unodar is experimental. Beyond the subset itself (`docs/SUBSET.md`), these are the limits to know about:

- **Arduino Uno only** (and clones with the Uno bootloader). **macOS and Linux**; Windows is untested in v0.7.
  `unodar flash` chooses a port only when exactly one is identified as an Uno: for a clone (CH340 and similar chips),
  pass `--port`, which `flash` prints for you. There is no `unodar run` (build, flash and serial monitor) yet.
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
- **Objects are places, not values:** an object of your class or a binding is a top-level `final` (or a field
  created in place), used only through its fields and methods: no locals, parameters, results or fields that refer
  to an object, no `==` on objects, and no inheritance (E018, E027). Composition gives the reuse.
- **Wrapped libraries are a fixed set** (EEPROM, SPI, SoftwareSerial, LiquidCrystal, DHT); anything else needs your
  own binding (`@CppClass`) or `cpp('…')`. No library that allocates (NeoPixel, Adafruit SSD1306), no I²C LCD
  backpacks, and nothing that needs arrays (`createChar`, SPI buffers); fixed-size lists are a later decision.
- **Library calls can block,** and that is documented, not rejected: an LCD `clear()` waits 2.3 ms, a DHT exchange
  6.2 ms with interrupts off for about 4 ms (`millis()` loses about 3 ms each time), a SoftwareSerial byte keeps
  interrupts off for its whole frame. Each wrapper's section in `docs/SUBSET.md` lists the measured waits.
- **Pins of member objects are not compared,** only those of widgets, top-level bound objects and objects the
  program uses (`SPI` takes 10–13, `Wire` A4/A5, `Serial` 0/1).
- **Widgets are static and few:** `Led`, `Button`, `Every`, `Watch`, `OnStart` only, every argument a compile-time constant
  (or, for `Watch` and `Led(on:)`, the name of a top-level signal), each widget a top-level `final` or written in
  `children`, one widget per pin. No release callback, and `Button` always uses the internal pull-up (button to GND).
- **Signals are static too:** top-level `final`s with a constant initial value, only in widget programs, used only
  through `.value` (not stored, passed, or compared themselves). Only a `Led` can follow a signal (`on:`).
- **Changes are delivered once per `loop()` pass**, after the buttons and timers: several writes in one pass are
  one delivery of the last value (a 0 → 1 → 0 blip is delivered as `0`), and a change made by a Watch is delivered
  one pass later. A Watch that writes its own signal, or Watches that write each other's signals in a circle
  (also through a `Computed`), are rejected (E025), even when the write is conditional.
- **`Computed` is one expression** over signals and Computeds declared above it and constants: no calls, no
  mutable variables (E026). Each read evaluates it, so keep it cheap.
- **Callbacks run inside `loop()`, one after another**, so a slow callback delays the others; `delay()` is
  rejected in callbacks (E023). An `Every` that falls behind catches up one tick per pass.
- **Libraries reserve RAM** before your code runs, out of 2048 B. Measured: Serial 175 B, Wire about 200 B more,
  Servo about 50 B, a SoftwareSerial 117 B, an LCD 36 B, a DHT sensor 19 B **plus Serial's 175 B even if you never
  use `Serial`** (its dependency links it). arduino-cli reports the total as "Global variables use …".
- **`cpp('…')` is not checked**, except that heap words are rejected (E020). What it does is up to you.
- **Wokwi on wokwi.com builds without `-fwrapv`.** The examples never overflow, so they behave the same there; Wokwi
  for VS Code runs the firmware you build with the flags. For a widget or signal program, add `unodar_widgets.h`
  to the wokwi.com project as a second file.
- **Widget and signal objects use RAM,** statically allocated: `Led` 2 B, `Button` 7 B, `Every` 8 B;
  `Signal<int>`/`Signal<double>` 5 B, `Signal<Int16>`/`Signal<Uint16>` 3 B, `Signal<bool>`/`Signal<Uint8>` 2 B; a
  watched `Computed` as a `Signal` of its type. A `Watch`, an unwatched `Computed` and the delivery itself use 0 B
  (measured with `avr-nm`).
- **Requirements:** a Dart SDK 3.13 or later. `unodar setup` installs the rest into `~/.unodar`: arduino-cli 1.5.1,
  `arduino:avr` 1.8.8 and the libraries pinned in `tool/arduino_libraries.txt` (`Servo` 1.3.0, `LiquidCrystal`
  1.0.7, `DHT sensor library` 1.4.7 and `Adafruit Unified Sensor` 1.1.15). On an Apple Silicon Mac the core's
  compiler runs under Rosetta 2. The runtime tests of a checkout also need Node.js 20.19+ (`unodar setup --dev`).
