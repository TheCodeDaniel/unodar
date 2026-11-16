# Phase 6 plan — Classes and library wrappers

**Status: in progress on the `phase-6` branch.** The maintainer approved D1–D10 as recommended on 2026-11-16 (D9 is
PRD §13.6, D10 is PRD §13.4), with two additions: the docs state that LiquidCrystal means the official
parallel-wired library (I²C backpack LCDs are not covered) and that Phase 8 displays need a heap-free driver
(Adafruit SSD1306 and NeoPixel call `malloc`); and the library manifest lists every dependency explicitly, checked
by a test (step 9), since CI installs with `--no-deps`.

Goal: a Flutter developer can organise a program into their own classes and use real Arduino libraries beyond
Servo and Wire, under the same rules as before: no heap, the fidelity rule (the generated C++ behaves exactly like
the Dart, or the construct is rejected), and every construct tested. PRD §8 row 6: simple classes become structs,
plus first-party library wrappers.

Exit gate:
- The goal program (`examples/thermostat`) compiles to flat, heap-free C++.
- In avr8js:
  - presses change the setpoint;
  - the LCD model shows the exact text expected;
  - the heater pin follows the hysteresis rule while a scripted A0 voltage sweeps;
  - the setpoint survives a simulated reset in EEPROM;
  - a negative control fails.
- Every new positive golden compiles with arduino-cli, has a size budget, and passes the no-heap check.
- Every construct has an avr8js behaviour test with a negative control.
- Every first-party binding passes its conformance probe (§3).
- Every rejection has a negative golden.
- Each wrapper's section in the docs says which of its checks ran in the simulator and which only on hardware.

## Goal program (with the recommended answers)

```dart
import 'package:unodar/unodar.dart';
import 'package:unodar/eeprom.dart';          // D8: one import per first-party library
import 'package:unodar/liquid_crystal.dart';

enum Mode { idle, heating }                   // D4

class Thermostat {                            // D1: fields, one constructor, methods, a getter
  final int hysteresis;
  Mode mode = Mode.idle;

  Thermostat({this.hysteresis = 1});

  void update(int temperature, int target) {
    if (mode == Mode.idle && temperature < target - hysteresis) {
      mode = Mode.heating;
    } else if (mode == Mode.heating && temperature > target + hysteresis) {
      mode = Mode.idle;
    }
  }

  bool get heating => mode == Mode.heating;
}

const int setpointAddress = 0;

final setpoint = Signal<int>(21);
final thermostat = Thermostat(hysteresis: 1);  // an object is a top-level final, like a bound object
final lcd = LiquidCrystal(12, 11, 5, 4, 3, 2); // rs, enable, d4–d7: pins checked against the widgets (@CppPin)
final heater = Led(pin: 13);

void show(int temperature) {
  lcd.setCursor(0, 0);
  lcd.print('T ');
  lcd.print(temperature);
  lcd.print(' set ');
  lcd.print(setpoint.value);
  lcd.setCursor(0, 1);
  if (thermostat.heating) {
    lcd.print('heating');
  } else {
    lcd.print('idle   ');
  }
}

void main() => runDevice(
      Device(board: Uno(), children: [
        OnStart(() {                            // D5: runs once in setup(), at its place in children
          lcd.begin(16, 2);
          final saved = EEPROM.read(setpointAddress);
          if (saved >= 5 && saved <= 35) setpoint.value = saved;
        }),
        heater,
        Button(pin: 6, onPressed: () { if (setpoint.value < 35) setpoint.value++; }),
        Button(pin: 7, onPressed: () { if (setpoint.value > 5) setpoint.value--; }),
        Every(Duration(seconds: 1), () {
          final temperature = analogRead(A0) * 40 ~/ 1023;   // DHT22 instead if step 19 lands
          thermostat.update(temperature, setpoint.value);
          heater.set(thermostat.heating);
          show(temperature);
        }),
        Watch(setpoint, (v) { EEPROM.update(setpointAddress, v); }),
      ]),
    );
```

Generated C++ (indicative; `#line` omitted; the reviewed goldens are authoritative):

```cpp
#include <Arduino.h>
#include <EEPROM.h>
#include <LiquidCrystal.h>
#include "unodar_widgets.h"

enum class Mode : uint8_t { idle, heating };

struct Thermostat {
  const int32_t hysteresis;
  Mode mode;
  constexpr explicit Thermostat(int32_t hysteresis) : hysteresis(hysteresis), mode(Mode::idle) {}
  void update(int32_t temperature, int32_t target);
  bool heating();
};

void show(int32_t temperature);
void unodar_onstart_0_callback();
// … the other callback prototypes, unodar_deliver()

unodar::Signal<int32_t> setpoint(21);
Thermostat thermostat(1);                 // constexpr: constant-initialized, no constructor code runs
LiquidCrystal lcd(12, 11, 5, 4, 3, 2);
unodar::Led heater(13);
// … buttons, every

void Thermostat::update(int32_t temperature, int32_t target) {
  if (mode == Mode::idle && temperature < target - hysteresis) {
    mode = Mode::heating;
  } else if (mode == Mode::heating && temperature > target + hysteresis) {
    mode = Mode::idle;
  }
}

bool Thermostat::heating() {
  return mode == Mode::heating;
}

void unodar_onstart_0_callback() {
  lcd.begin(16, 2);
  const int32_t saved = EEPROM.read(setpointAddress);
  if (saved >= 5 && saved <= 35) {
    setpoint.set(saved);
  }
}

void setup() {
  unodar_onstart_0_callback();            // children order
  heater.begin();
  unodar_button_0.begin();
  unodar_button_1.begin();
  unodar_every_0.begin();
  unodar_deliver();                       // initial values, including a setpoint loaded in OnStart
}
```

## 1. User-defined classes (D1–D3)

### The central rule: an object is a place, not a value

Dart objects are references and C++ objects are values. The two differ exactly where an object is **copied**:

| Dart | Dart meaning | Naive C++ | Same? |
|---|---|---|---|
| `var b = blinker; b.count++;` | Changes `blinker.count` (an alias) | Changes a copy | **No** |
| `void bump(Blinker b) { b.count++; }` | Changes the caller's object | Changes a copy | **No** |
| `Blinker(this.led)` given `led` | The field refers to the global `led` | The field holds a copy of `led` | **No** |
| `a == b`, `identical(a, b)` | Identity, unless `==` is overridden | No `operator==`, or a memberwise compare | **No** |
| `Blinker make() => Blinker(3);` | A new heap object | A stack copy | Only if immutable |

**Recommendation (D1, D2).** An object of a user class is either a top-level `final` created by its constructor,
like a bound object (`final thermostat = Thermostat(hysteresis: 1);`), or a `final` field created in place inside
another class. Its fields and methods are the only way to use it:
- no locals, parameters, return values or fields that refer to an object;
- no `=`, no `==`, no `identical`, no `this` as a value.

Then every Dart reference names exactly one statically known object, the C++ names that object directly, and no
copy is ever made. Reference semantics and value semantics cannot differ. This is the E018 rule for bound objects
and the E024 rule for signals, applied once more, so users meet one rule for every "static object".

### What is accepted and what is rejected

| Construct | Phase 6 | C++ / code | Why |
|---|---|---|---|
| `class C { … }`, `final class C { … }` | Accepted | `struct C { … };` | All members public. Dart privacy (`_x`) is checked by the analyzer, and the program is one library. |
| Instance fields | Accepted: `final` or mutable, of a supported type, enum type, or (composition) a user/binding class created in place | Members, declaration order | Size is the sum of the fields: AVR alignment is 1 byte. |
| `late` fields, nullable fields | E027, E009 | | `late` needs an "initialized?" flag and throws in Dart. |
| One unnamed generative constructor | Accepted, with initializing formals (`this.x`), named parameters with constant defaults or `required`, an initializer list | `constexpr` constructor when every member allows it | Named parameters give the Flutter-style `Thermostat(hysteresis: 1)`. They are passed positionally, as for bindings. |
| Constructor body, `factory`, named, redirecting, `const` constructors, more than one constructor | E027 | | **A body would run at a different time.** Dart runs a top-level `final`'s constructor lazily, at first use; C++ runs it before `main()` calls Arduino's `init()`, before timers, `millis()` or `Serial` work. Without a body, and with only constant arguments (E015), construction is pure and the C++ is constant-initialized, so the timing cannot be observed. Setup work goes into a method called from `OnStart` (D5) or `setup()`. |
| Field initializers, initializer list | Accepted when constant over constants and constructor parameters (E015) | Member initializers | C++ initializes members in declaration order whatever the list order; with pure initializers the order cannot be observed. |
| Instance methods, getters | Accepted. Same signature rules as functions (E011), same body rules. | Member functions, defined after the globals | A method is a function with an implicit receiver. Instances share the code. |
| `this.x`, bare `x` for a field | Accepted | `this->x`, `x` | Dart and C++ resolve names the same way: local, then member, then top level. |
| Setters, operators (`operator +`, `==`), overriding `toString`/`hashCode`/`noSuchMethod` | E027 | | A setter would be a second way to write a field; operators and `==` would make objects values. |
| Static `const`/`final`/mutable fields, static methods | Accepted; initializers constant (E015) | `static constexpr` / `static` members, defined out of class | These are globals and functions in the class's namespace; with constant initializers Dart's lazy statics cannot be told apart from them. |
| `extends`, `implements`, `with`, `abstract`, `sealed`, `base`, `interface`, `mixin`, `mixin class` | E027 | | See "Inheritance" below. |
| Type parameters on a class | E027 | | Like functions (E011). |
| Objects as parameters, locals, returns, fields that refer to another object | E018 | | The aliasing rows of the table above. D2 has the alternative. |
| Fields of signal or widget type | E024, E022 | | §2. |
| A class used as a field type before its declaration; a composition cycle | E015 (forward reference), E027 | Class definitions in source order | Declare before use, like top-level initializers. A cycle means an infinitely large object, which Dart would overflow the stack constructing. |
| Simple `enum` | Accepted (D4) | `enum class E : uint8_t { … };` | See "Enums". |
| Enhanced enums (fields, constructors, methods, `implements`, `with`) | E028 | | Later, once simple enums prove out. |

The table answers the brief's list: fields yes, constructors yes (one, with no body), methods yes, static members
yes, enums yes (simple ones), and no inheritance, abstract classes, interfaces, virtual dispatch or mixins.

### Inheritance, interfaces, virtual dispatch, mixins: rejected

Every object is a place, so the static type of a receiver is always its exact class. Virtual dispatch would
therefore do nothing for user code, except in one case, and that case is a fidelity trap:

```dart
class Base { void run() { step(); } void step() { … } }
class Fast extends Base { @override void step() { … } }
```

In Dart, `fast.run()` calls `Fast.step`: the call on `this` is dispatched dynamically. A plain C++ translation
calls `Base::step`, which is a silent miscompile. A faithful translation needs one of:
- `virtual`: on AVR, vtables are copied into **RAM** at startup, plus a 2-byte pointer per object, plus indirect
  calls the compiler cannot inline;
- per-subclass copies of every inherited method: flash duplication, and super-call and constructor chaining rules.

Either way the result is code reuse, which composition already gives, without polymorphism, which needs references
(D2). **Cost of allowing it now:** every class rule gains super, override and constructor-chaining cases; E016,
E023 and E025 need dispatch-aware call graphs; and AVR pays RAM for every vtable. It fits better once objects can
be passed (D2), because that is when interfaces start to pay off.

Mixins have the same problem as `extends`, and they also linearize. `implements` without inheritance only matters
for parameters (D2).

### Alternatives for objects as values (D2, D3), and their cost

- **D2 alternative: references.** `void flash(Blinker b)` becomes `void flash(Blinker &b)`, and `final b = blinker;`
  becomes `Blinker &b = blinker;`. This is faithful for parameters and for locals that are never reassigned,
  because C++ references alias exactly like Dart references, and every object is a global, so no reference can
  dangle. Its cost:
  - `==` must become an address comparison;
  - fields that refer to another object need constant addresses;
  - E016, E023 and E025 must assume that any method of the class may run on any instance (conservative, but it
    rejects more programs);
  - interfaces become the next request at once.

  Recommended for Phase 7 or later, together with `implements`.
- **D3 alternative: immutable value classes.** A class with only `final` fields of value types, no identity
  (`==` and `identical` rejected) and no mutable state behaves the same with copy semantics: `Color mix(Color a,
  Color b) => Color(…)` can be a C++ struct passed and returned by value on the stack, with no heap. Its cost:
  - a second kind of class, with its own rules;
  - stack use per copy, which is bounded because recursion is rejected, but adds up;
  - copies hidden in what looks like passing a reference.

  Most of its value comes with collections, so the recommendation is to decide it together with fixed-size lists
  (D10).
- **Heap or pool allocation** (`Blinker()` anywhere): rejected by NG5.

### Enums (D4)

`enum Mode { idle, heating }` becomes `enum class Mode : uint8_t { idle, heating };`, at most 256 values (E028).

| Accepted | C++ |
|---|---|
| `Mode.idle` | `Mode::idle` |
| `==`, `!=` | the same (Dart enums have no `<`) |
| `m.index` | `uint8_t(m)`, an `int` read that gets the existing 32-bit widening |
| enum-typed variables, fields, parameters, returns, `const`s | the C++ enum type |
| `Signal<Mode>` and `Watch` on it | `unodar::Signal<Mode>` (`set()` compares with `!=`, which `enum class` supports) |

Rejected (E028): `Mode.values` (a list), `.name`, and enhanced enums. Printing an enum (`Serial.print(mode)`) is
E009, with the help "print `mode.index`". (Dart prints `Mode.idle`. A name table in flash is possible later.)
Enum value names go through E014: a value named `min` would be replaced by Arduino's macro even inside `Mode::`.

`switch` on enums and ints (constant `case` patterns only; Dart 3 cases do not fall through, so every case
becomes `case …: { … } break;`) is useful with enums but is not a class feature, so it comes **after the cut line**
(step 18). `if`/`else` chains work without it.

## 2. How classes interact with what exists

- **Signals.**
  - A method may read and write top-level signals like any function, and callbacks may call methods.
  - Signal *fields* are rejected (E024, "a signal must be a top-level `final`"). A Watch must name its source, and
    delivery is generated per signal. A field signal would need paths (`Watch(panel.count, …)`), per-instance
    write edges for E025, and per-instance delivery code. That is possible later, because objects are places, but
    it is not needed to organize code.
  - `Signal<T>` also accepts enum types (D4). Signals of class types are E009, because objects are not values.
- **Watch and widgets.**
  - Widget fields are rejected (E022, the existing "a widget is a top-level `final` or written in `children`").
  - User objects are not widgets. `Widget` stays `final`, so listing an object in `children` is a Dart type error
    (E007).
  - Methods may call widget handles (`heater.set(…)`), like functions, and the bound-Led rule (E022) applies in
    method bodies too.
  - The Flutter way of organizing a UI, a user class with a `build()` that returns widgets, would have to be
    expanded statically at compile time. That is the composite-widget question, D6, recommended for Phase 8,
    together with layout.
- **E021–E023.**
  - Classes are allowed in both kinds of programs: sketches and widget programs.
  - E023 (`delay()` in callbacks) searches through methods and getters as it does through functions. A method
    reached from a callback must not call `delay()`.
  - `OnStart` (D5) is exempt from E023: it runs once in `setup()`, before anything is polled, so `delay()` there
    stops nothing.
- **Computed.** A Computed may read `final` fields of objects; they cannot change, just as top-level `final`s may
  already be read. Reading a mutable field is E026, the same rule as for a mutable variable, and a getter or method
  call is E026 ("no calls").
- **Call graph.** Its nodes become functions, methods, getters and static methods.
  - E016 (recursion) covers methods.
  - E025 (reactive cycles) follows writes through methods. This is exact, because signals cannot be per-instance.
  - E013 treats a method or getter call as a user-function call, and a read of a mutable field of a top-level
    object as a read of mutable top-level state.
- **Non-capturing callbacks.** Closures inside methods, and method tear-offs (`onPressed: thermostat.reset`), are
  E012. Write `() { thermostat.reset(); }`, as for functions today.
- **Bindings inside classes (composition).** `final Servo arm = Servo();` as a field becomes a member `Servo arm;`.
  - Binding constructors are not `constexpr`, so such a class is initialized dynamically before `setup()`. This is
    the existing documented deviation for bound objects: "constructed before `setup()` runs".
  - Pins in its constructor go through `@CppPin` (§3).

## 3. Library wrappers (D7–D9)

### Which libraries (D7)

Each library was checked against its source on 2026-11-15, using the index versions of that day:

| Library | Source | Why it's included | Notes from the source |
|---|---|---|---|
| **EEPROM** | ships with `arduino:avr` | Persistence: the first thing a real gadget needs (setpoints, counters) | Header-only, inline, no heap |
| **SPI** | ships with `arduino:avr` | The bus under most displays, SD cards and radios, and what other wrappers build on | `SPISettings` is a value object passed by value, so it needs a small shim header (below) |
| **SoftwareSerial** | ships with `arduino:avr` | GPS, Bluetooth (HC-05) and other serial modules while `Serial` stays the USB console | Derives from `Print`, so it needs `@CppPrint`. 64-byte RX buffer, shared |
| **LiquidCrystal 1.0.7** | library index, maintained by Arduino | The 16×2 LCD in every starter kit. Text output without waiting for Phase 8 | Derives from `Print`. `begin()` waits about 60 ms; `clear()`/`home()` 2 ms; each character about 100 µs |
| **DHT sensor library 1.4.7** (+ Adafruit Unified Sensor 1.1.15, its declared dependency) | library index, Adafruit | The most common beginner sensor (temperature and humidity) | `read()` waits 20 ms (`delay(20)`) and then locks interrupts while it times 40 bits (several ms; `millis()` loses ticks). It returns a cached value if it read less than 2 s ago. NaN on failure. **After the cut line.** |

Not proposed:
- **Adafruit NeoPixel 1.15.5** allocates its pixel buffer with `malloc` (`updateLength()`, `Adafruit_NeoPixel.cpp:182`).
- **FastLED** is static, but it needs a `CRGB leds[N]` array (fixed-size lists, D10) and template arguments
  (`addLeds<WS2812B, 6, GRB>`). Revisit after D10.
- **Adafruit SSD1306 2.5.17** allocates its 1 KB frame buffer with `malloc` in `begin()` (`Adafruit_SSD1306.cpp:499`):
  half the Uno's RAM. Which OLED driver to use (U8g2 in page mode, or SSD1306Ascii, both heap-free) belongs to
  Phase 8, with the `Oled` widget.
- **LiquidCrystal I2C 1.1.2** is popular, but it is a community fork, not maintained by Arduino. "LiquidCrystal"
  in this phase means only the official parallel-wired library; I²C backpack LCDs are not covered (maintainer
  decision). It is a good
  later candidate: avr8js models TWI, so it is testable through a PCF8574 model.
- **Stepper** blocks inside `step(n)` for a time that depends on its argument.

The no-heap rule is enforced by the existing `avr-nm` check on a golden that calls every wrapped method, so a
library that allocates cannot ship by accident.

### How wrappers are written and imported (D8)

- Each wrapper is an ordinary binding (`@CppHeader`/`@CppClass`/`@CppType`/`@CppRange`) in its own library,
  `package:unodar/eeprom.dart`, `spi.dart`, `software_serial.dart`, `liquid_crystal.dart`, `dht.dart`, imported
  explicitly.
  - E005 accepts exactly these imports.
  - A wrapper's names (E014, the registry) exist only when it is imported, so `lcd` or `Dht` cannot clash in a
    program that doesn't use them.
- **Shim headers.** Where a C++ API cannot be bound directly, a wrapper may come with a fixed, hand-written
  header `runtime/unodar_<lib>.h`. It is embedded, equality-tested, written next to the `.ino` only when used, and
  tested on its own, exactly like `unodar_widgets.h`. SPI is the only planned one:
  `SPI.beginTransaction(SPISettings(clock, order, mode))` takes an object by value, so the shim offers
  `unodar::spiBeginTransaction(uint32_t, uint8_t, uint8_t)`.
- **`@CppPrint()`** on a binding class gives its `print`/`println` the dispatch `Serial` already has:
  - a string literal becomes `F("…")`;
  - a `bool` prints `true`/`false`;
  - a `double` takes `digits:`.

  LiquidCrystal and SoftwareSerial need it; without it, `lcd.print(true)` would print `1`.
- **`@CppPin()`** on a binding constructor parameter marks it as a pin:
  - constant pins are range-checked 0–19 (E004);
  - pins are compared with every widget pin and every other `@CppPin` (E022).

  Today a `Button(pin: 2)` next to `LiquidCrystal(…, 2)` compiles silently, and both break. Only constructor
  arguments can be checked: they are constants, while method arguments such as `servo.attach(9)` are not always.
- **Blocking library calls.** These are documented, not rejected. E023 exists because `delay(1000)` stops every
  button. A library's fixed waits (LCD `clear()` 2 ms, DHT `read()` about 25 ms once every 2 s) only delay polling,
  and the 50 ms debounce absorbs them. Each wrapper's section lists the worst-case wait and interrupt-off time of
  each method, **measured in avr8js**. A library whose wait depends on its arguments (Stepper) is not wrapped.

### Pinning and installing versions in CI

- **One manifest, `tool/arduino_libraries.txt`.** It holds `Servo@1.3.0`, `LiquidCrystal@1.0.7`,
  `DHT sensor library@1.4.7` and `Adafruit Unified Sensor@1.1.15`.
  - It is read by `.github/workflows/ci.yml`, `tool/check_arduino.sh` and the `arduino` test gate, and later by
    `unodar setup` (PRD §8.1).
  - CI installs each line with `arduino-cli lib install --no-deps` and fails unless `arduino-cli lib list` matches
    the manifest exactly. Every dependency is therefore listed and pinned: none floats in through automatic
    dependency resolution.
  - `~/Arduino/libraries` joins the CI cache, keyed on the manifest's hash.
  - Locally, a missing library fails `check_arduino.sh`, or skips the `arduino` tests, with the exact install
    line.
- EEPROM, SPI, SoftwareSerial and Wire ship with `arduino:avr@1.8.8`, which is already pinned.
- Size budgets and conformance probes are measured against these exact versions. A version bump gets a dedicated
  commit, like a budget change.

### A tool that drafts bindings from headers? (D9, PRD §13.6)

**Recommendation: no generator in Phase 6, and a binding conformance probe instead.**

- **What the probe does.** For every first-party binding, a test generates a C++ file that calls each bound method
  with arguments of exactly its declared `@CppType`s. It checks that each result has the declared return type, using
  a five-line `same_type` template, because AVR has no `<type_traits>`. arduino-cli compiles the file.
- **What it catches.** A binding that has drifted from its header: a wrong overload, a wrong return type, a renamed
  method after a version bump. It is about 150 lines, reuses the registry, and runs on every binding, user
  bindings included (via a CLI flag later).
- **A generator's cost.** `clang -Xclang -ast-dump=json` on the header, with the AVR include paths:
  - a clang dependency that the Arduino toolchain does not have;
  - AVR macros (`PROGMEM`, `__attribute__`);
  - about 1000 lines plus tests;

  and its draft still needs a human for `@CppRange`, `@CppPin`, heap use and blocking times. Those are the parts
  that take thought. Five wrappers of 30–80 lines each don't justify it.
- **Next step.** Each wrapper step records in DECISIONS how long the binding took and what was hard, so that
  §13.6 can be answered with data.

## 4. Testing honesty

avr8js 0.21.1 models the GPIO ports, timers, USART, ADC, **SPI, TWI (I²C) and EEPROM** (checked in
`node_modules/avr8js`). External chips do not exist in it. The runner gains a small model for each device a wrapper
talks to, and each model has its own runner test with a negative control (step 12 and the wrapper steps). The pin
log gains cycle timestamps, which bit-level protocols need.

| Wrapper | Compile, budget, no heap, conformance | Proven in avr8js | Only on a real board (or Wokwi, visually) |
|---|---|---|---|
| EEPROM | yes | Bytes written and read through `AVREEPROM`. `update()` skips equal bytes (write count from the backend). Values survive a reset (a second run on the same EEPROM file). | Write time (3.3 ms per byte) and endurance (about 100,000 writes per cell); corruption on brown-out |
| SPI | yes | Bytes on MOSI and the bytes a scripted slave returns (`AVRSPI`). The SPCR/SPSR settings derived from clock, order and mode. Chip select in the pin log. | Real chips at speed; signal integrity |
| SoftwareSerial | yes | TX bytes decoded from the cycle-stamped pin log, with bit timing within tolerance. RX by scheduled bit edges; 64-byte overflow. | Baud tolerance against real devices' clocks; interaction with other interrupt users |
| LiquidCrystal | yes | An HD44780 model in the runner decodes the 4-bit protocol on its pins: the init sequence, the screen text (DDRAM), the cursor, and the minimum timings (enable pulse ≥ 450 ns, ≥ 37 µs between commands). | Contrast, the clone controllers' slower timings, the look (Wokwi `lcd1602`) |
| DHT (cut line) | yes | A DHT22 model answers the start pulse with a 40-bit frame: the parsed temperature and humidity, a bad checksum giving NaN, the 2 s cache, and the `millis()` ticks lost while interrupts are off (measured and documented). | Sensor accuracy, wiring and pull-up, timing margins of real sensors (Wokwi has a DHT22) |

Classes and enums are pure computation and pins, so everything about them is provable: goldens, compile, budget,
`avr-nm`, and avr8js behaviour with a negative control per construct (for example, fields emitted `static`, which
makes two instances share their state).

## 5. Memory and flash cost (estimates; measured in step 21)

These are fixed at compile time. They are estimates from the library sources and Phase 5 measurements; step 21
replaces them with measurements, as Phase 5 did.

| Feature | RAM | Flash |
|---|---|---|
| Object of a user class | sum of its fields (`int`/`double` 4, `Int16`/`Uint16` 2, `bool`/`Uint8`/enum 1); no padding, no vtable. A class without fields: 1 B (the C++ minimum), or 0 if the linker drops it | Constructor 0 B (constant-initialized) |
| Method or getter | 0 B | As the same top-level function. The receiver is a 2-byte pointer in registers, often removed by LTO for a single instance: estimate +0–10 B per call. Instances share the code. |
| Static field | as a global (`static const`: 0 B, folded) | 0 B |
| Composition | sum of the members | Constructors of binding members run before `setup()`, as today |
| Enum | 1 B per variable or field; `Signal<Mode>` 2 B | `==` is an 8-bit compare; `.index` widened only where it is used |
| `OnStart` | 0 B | One function and a call (about 4–10 B) |
| `@CppPin`, `@CppPrint`, conformance probe | 0 B | 0 B (compile-time only) |
| EEPROM | 0 B | About 20–60 B per kind of call (inline `eeprom_read_byte`/`eeprom_write_byte`) |
| SPI | about 1–3 B (SPIClass statics) | About 150–250 B for `begin` + `transfer` + one transaction |
| SoftwareSerial | 64 B RX buffer (shared) + about 20 B per object + vtable | About 1.2–1.8 KB, including `Print` |
| LiquidCrystal | about 25 B per object + `Print` vtable | About 1.0–1.5 KB, plus `Print`'s number formatting (about 0.5 KB) if nothing else links it |
| DHT | about 15 B per object | About 1–1.5 KB, plus float code if nothing else links it |
| Goal program | about 90–120 B (no `Serial`) | About 4–5 KB |

## 6. New diagnostics (next free: E027)

| Code | Rule | One-line example → message | Help |
|---|---|---|---|
| E027 | Class declarations: `extends`/`implements`/`with`, class modifiers other than `final`, `mixin` declarations, type parameters, a constructor body, `factory`/named/redirecting/`const` constructors or more than one, setters, operators, overriding `toString`/`hashCode`/`==`, `late` or `external` members, a composition cycle | `class Fast extends Blinker {}` → "a class cannot extend another class in this version ('Fast' extends 'Blinker')." | "Give 'Fast' a field of type 'Blinker' instead (composition), or merge the two classes." |
| E027 | (constructor body) | `Blinker(this.pin) { pinMode(pin, OUTPUT); }` → "a constructor cannot have a body: objects are created before setup() runs, not when Dart would first use them." | "Move this code into a method, e.g. `void begin()`, and call it from OnStart or setup()." |
| E028 | Enums: enhanced enums (fields, constructors, methods, `implements`/`with`), more than 256 values, `.values`, `.name` | `Serial.println(mode.name);` → "the name of an enum value is not available in this version." | "Print `mode.index` instead." |

Existing codes gain cases (wording only; each problem is reported once, under the family users search by):
- **E005:** classes are no longer E005; extensions, extension types and typedefs still are; the wrapper imports
  are accepted.
- **E009:** field types; printing an enum; `Signal<ClassType>`.
- **E011:** method signatures.
- **E012:** closures in methods; method tear-offs.
- **E013:** method calls and mutable field reads.
- **E014:** names of classes, fields, methods, enums and enum values.
- **E015:** constructor arguments; field initializers; a class used before its declaration.
- **E016:** recursion through methods.
- **E017:** `@CppPin`/`@CppPrint` misuse.
- **E018:** retitled "Object misuse" (bound objects and objects of your classes): objects as values, `this` as a
  value, object-typed locals, parameters and returns.
- **E022:** `@CppPin` conflicts; widget fields; `OnStart` placement.
- **E023:** search through methods; the `OnStart` exemption.
- **E024:** signal fields.
- **E025:** writes through methods.
- **E026:** field reads and getter calls in a Computed.

## 7. Steps (one construct per commit, test first)

Every construct step adds its goldens first, and in the same commit:
- each positive golden is compiled by arduino-cli, gets its first-measurement size budget, and passes the
  `avr-nm` no-heap check;
- the construct gets an avr8js behaviour test with a negative control;
- each wrapper step also adds the wrapper's conformance probe and its "Verified:" line in SUBSET.

| # | Step | Test written first |
|---|---|---|
| 1 | (**done**, a7b6ffc) This plan and the decisions | — |
| 2 | (**done**) Spec, after the answers: SUBSET "Your own classes", "Enums", "Libraries" (one section per wrapper); DIAGNOSTICS E027, E028 and the reworded codes; PRD status, §13.4 and §13.6. Examples that change output later wait in `docs/drafts`, as in Phase 3. | `docs_test` stays green |
| 3 | Classes I: declaration, fields, one constructor (initializing formals, named parameters, initializer list), objects as top-level `final`s, field reads and writes from outside (`t.mode = …`, `c.count++`); E027, E018, E015, E014, E009 | Goldens `class_fields` + negatives; avr8js: two instances keep independent state; control: fields emitted `static` |
| 4 | Classes II: instance methods and getters, implicit and explicit `this`; the call graph through methods (E016, E023, E025, E013); tear-offs (E012) | Goldens `class_methods`, `e016_method_recursion`, `e023_delay_in_method`, `e025_write_in_method`; avr8js: a method on one instance changes only that one; control: a body emitted against the wrong object |
| 5 | Static members: `static const`/`final`/mutable fields, static methods | Golden `class_static`; avr8js: a static counter shared by instances; control: a per-instance copy |
| 6 | Composition: `final` fields of a user class or binding type, created in place, in declaration order | Golden `class_composition`; avr8js: nested state, and a Servo member driving pin 9 (pin log); control: members constructed in the wrong order |
| 7 | Enums: declaration, `==`/`!=`, `.index`, enum-typed variables, fields, parameters and returns, `Signal<Mode>` with `Watch`; E028; E009 for printing | Goldens `enum_basics`, `enum_signal` + negatives; avr8js: a state machine's transitions, `mode.index * 1000`; control: `.index` without the widening |
| 8 | `OnStart` (D5): a widget, run in `setup()` at its `children` position, before the setup delivery; E023 exemption; writes delivered by the setup delivery | Golden `on_start`; avr8js: the order of `begin()` and `OnStart` in the pin log, and a signal written there printed once at boot with its new value; control: `OnStart` emitted after the setup delivery |
| 9 | Library infrastructure: `tool/arduino_libraries.txt` (Servo moves into it; every dependency listed) read by CI, `check_arduino.sh` and the gate; `package:unodar/<lib>.dart` imports (E005); shim headers through `runtime_files.dart` | `cli_test`, `golden_test`; CI job; a missing library gives the install line; a test that every `depends=` of a manifest library is in the manifest |
| 10 | `@CppPin` (E017, E004, E022) on the existing bindings where it applies | Goldens `e022_binding_pin_conflict`, `e017_cpp_pin` |
| 11 | Binding conformance probe for Wire and Servo | Probe test; control: a deliberately wrong `@CppType` must fail it |
| 12 | Runner: cycle-stamped pin log, `--spi` scripted slave, `--eeprom FILE` backend with a write count | Runner tests on hand-written sketches, each with a negative control |
| 13 | EEPROM wrapper (`read`, `write`, `update`, `length`; address `@CppRange(0, 1023)`) | Golden `eeprom`; avr8js: persistence across two runs, `update()` write count; control: `update` bound to `write` |
| 14 | SPI wrapper + `unodar_spi.h` shim (`begin`, `transfer`, `beginTransaction`/`endTransaction`; `MSBFIRST`, `SPI_MODE0`–`3`) | Golden `spi`; shim tested on its own; avr8js: scripted slave transcript, SPCR bits; control: wrong mode bits |
| 15 | `@CppPrint` dispatch for `Print`-derived bindings, tested on a user `SoftwareSerial` binding (the SUBSET example) | Golden `cpp_print`; avr8js: bools print `true`/`false`; control: Arduino's plain `print(bool)` |
| 16 | SoftwareSerial wrapper (`begin`, `print`/`println`, `available`, `read`, `write`) | Golden `software_serial`; avr8js: TX decoded from the pin log, RX by scheduled edges; control: wrong baud |
| 17 | LiquidCrystal wrapper (4-bit constructor with `@CppPin`, `begin`, `clear`, `home`, `setCursor`, `print`/`println`, `display`/`noDisplay`, `cursor`/`noCursor`, `blink`/`noBlink`, `scrollDisplayLeft`/`Right`) + runner HD44780 model | Golden `liquid_crystal`; avr8js: exact screen text and minimum timings; control: a wrong row offset |
| — | **Cut line.** Everything above stands alone. Below is optional and can be dropped without breaking anything above. Steps 14 and 16 can also be dropped one at a time: nothing later depends on them. | |
| 18 | (optional) `switch` statements on enums and ints, with constant cases | Goldens `switch_enum`, `e002_switch_patterns`; avr8js; control: a missing `break` (fallthrough) |
| 19 | (optional) DHT wrapper + runner DHT22 model; `Adafruit Unified Sensor` pinned | Golden `dht`; avr8js: values, NaN on a bad checksum, the 2 s cache, lost `millis()` ticks measured; control: a wrong bit threshold |
| 20 | (only if D3 = include) immutable value classes | Golden `value_class`; avr8js; control: a mutable field accepted |
| 21 | Size-budget review (dedicated commit): every Phase 6 budget, RAM per object golden, §5 replaced by measurements | `size_budgets.dart` |
| 22 | `examples/thermostat` (the goal program; DHT22 instead of the potentiometer if step 19 landed) with `wokwi/` (lcd1602, two buttons, a potentiometer or DHT22, an LED as the heater), built by `tool/check_arduino.sh` | avr8js goal test: bouncing presses, the A0 sweep, the exact LCD text, the heater pin log, the setpoint kept across a reset; negative control |
| 23 | Final docs pass (README status and known limits, PRD status, PLAN); full check suite; end report | — |

## 8. Open decisions (for the maintainer)

| # | Decision | Recommendation | Cost of the alternative |
|---|---|---|---|
| D1 | Class subset | "Objects are places": fields, one generative constructor without a body (named parameters, initializing formals, initializer list), methods, getters, static members, composition. No inheritance, abstract classes, interfaces, mixins, virtual dispatch, operators, setters, constructor bodies or generics (E027). No signal or widget fields. | Inheritance now: a silent miscompile unless every `this` call is dispatched; vtables in AVR RAM, or duplicated methods; super and override rules in E016/E023/E025. Constructor bodies: code that runs before Arduino's `init()`, where Dart would run it at first use. |
| D2 | Objects as parameters or locals | No: objects are used only through fields and methods (E018, as for bound objects) | References (`T&`) are faithful but bring address equality, conservative per-class call graphs, and the immediate need for interfaces. Better done together with `implements`, later. |
| D3 | Immutable value classes (pass and return by value) | Not in Phase 6; decide together with D10 (collections) | A second kind of class with its own rules; hidden stack copies. Little use without lists. |
| D4 | Enums, and `switch` | Simple enums (to `enum class : uint8_t`), including `Signal<Enum>`; `switch` after the cut line; enhanced enums later (E028) | No enums: state machines on `int` constants (less readable, no type checking). Enhanced enums now: fields and constructors per value, more rules. |
| D5 | Start hook for widget programs | `OnStart(() { … })`, a widget in `children`, run once in `setup()` at its position, before the initial delivery; `delay()` allowed there | Today a widget program has **nowhere** to call `lcd.begin()` or `servo.attach()`. `Device(onStart: …)`: one place only, and the order relative to the widgets is fixed. Auto-`begin` per binding: every binding row needs a "setup call", and arguments such as `begin(16, 2)` stay unexpressed. |
| D6 | Composite widgets (user classes with a `build()` returning widgets) | Phase 8, with display layout | Static expansion of `build()` (constant arguments, generated names per instance) now, before layout needs it |
| D7 | Library set and versions | EEPROM, SPI, SoftwareSerial (core), LiquidCrystal 1.0.7, DHT sensor library 1.4.7 + Adafruit Unified Sensor 1.1.15 (after the cut line). Not NeoPixel or SSD1306 (they use `malloc`), and not LiquidCrystal I2C (a fork) | An I2C LCD instead of a parallel one: fewer wires for users, but a community library, a PCF8574 model in the runner, and an address to configure. NeoPixel only through FastLED, after D10. |
| D8 | How wrappers are imported | `import 'package:unodar/eeprom.dart';`, one library per wrapper; names reserved only when imported | Everything in `unodar.dart`: no extra import, but every wrapper name is reserved (E014) in every program, and the API surface grows with each library. |
| D9 | PRD §13.6: binding generator | No generator in Phase 6; a binding conformance probe for every binding; time and pain recorded per wrapper | A clang-based draft tool: a new toolchain dependency, AVR macro handling, about 1000 lines, and it still needs a human for ranges, pins, heap and blocking. |
| D10 | PRD §13.4: fixed-size lists | Not in Phase 6. Consequences: no FastLED/NeoPixel, no `LiquidCrystal.createChar`, no value classes; buffers stay inside libraries | `FixedList<T, N>` now: a static array type, bounds behaviour (Dart throws a `RangeError`, so every index needs a check or a proof), iteration, and probably `for`-`in`. A phase-sized design of its own. |

## Extension hooks kept

- Classes lower into the existing IR, with an `IrStruct` (fields, constructor, methods as `IrFunction`s with a
  receiver). Methods reuse the function pipeline, so every body rule applies unchanged.
- Objects reuse the bound-object path (static globals, constant arguments, method calls), so a reference-passing
  extension (D2) only changes E018 and the emitter's parameter form.
- Wrappers are bindings, plus at most one shim header and a manifest line, so a new library is data.
- Runner device models are separate modules with a common interface (pins, SPI, TWI), so a PCF8574 (I²C LCD) or
  a WS2812 decoder can be added later.

---

# Phase 5 plan — Signals

**Status: done (2026-11-14), tagged v0.5.0.** The
maintainer approved D1–D7 as recommended (D6 is PRD §13.3), and every step was built in order, one construct per
commit. Five fixes landed between steps as their own commits: the generated-name clash (E014, before step 3), the
most vexing parse in object declarations (before step 4), and, before step 10, the proof of the anonymous RAM bytes,
the E022 wording for an unlisted Watch, and a golden for a `_` Watch parameter. Phase 6 (classes, library wrappers)
is out of scope.

Final state: 409 tests (19 in `packages/unodar`, 390 in `packages/unodar_compiler`), none skipped; 147 goldens (36
positive, each compiled with arduino-cli, size-budgeted, and checked heap-free); the signal runtime tested on its
own in avr8js with three negative controls; every construct's behaviour tested in avr8js with a negative control;
the goal program `examples/counter` run in avr8js (bouncing presses, exact serial transcript and pin log) with a
negative control, and built by `tool/check_arduino.sh`.

Goal: a Flutter developer can hold state and react to it, with no heap, no capturing closures, and generated C++
that behaves exactly as documented in `docs/SUBSET.md` (fidelity rule). PRD §8 row 5: `Signal<T>` (value + dirty
flag), binding to widgets, no heap.

Exit gate: the goal program (`examples/counter`) compiles to flat, heap-free C++; in avr8js, debounced presses
change the count, the serial transcript and the LED pin log match the documented delivery rules exactly, and a
negative control fails; every new positive golden compiles with arduino-cli, has a size budget and passes the
no-heap check; every construct has an avr8js behaviour test with a negative control; every rejection has a
negative golden; the docs are accurate.

## Goal program (with the recommended answers)

```dart
import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final isOdd = Computed(() => count.value % 2 == 1);   // D6; without Computed see below

final led = Led(pin: 13, on: isOdd);                   // D7: the LED follows the signal
final plus = Button(pin: 2, onPressed: () { count.value++; });
final clear = Button(pin: 3, onPressed: () { count.value = 0; });

void main() => runDevice(
      Device(board: Uno(), children: [
        led, plus, clear,
        Watch(count, (v) { Serial.println(v); }),
      ]),
    );
```

Without `Computed` (if D6 defers it) the same program is the maintainer's sketch:
`final led = Led(pin: 13);` and `Watch(count, (v) { led.set(v % 2 == 1); Serial.println(v); })`.

Generated C++ (indicative; `#line` omitted; the reviewed goldens are authoritative):

```cpp
#include <Arduino.h>
#include "unodar_widgets.h"

constexpr int32_t unodar_mod(int32_t a, int32_t b) { … }

bool unodar_isOdd_compute();
void unodar_plus_onPressed();
void unodar_clear_onPressed();
void unodar_watch_0_callback(int32_t v);
void unodar_deliver();

unodar::Signal<int32_t> count(0);
unodar::Signal<bool> isOdd(false);   // Computed: the last delivered value
unodar::Led led(13);
unodar::Button plus(2);
unodar::Button clear(3);

bool unodar_isOdd_compute() { return unodar_mod(count.value(), 2) == 1; }
void unodar_plus_onPressed() { count.set(count.value() + 1); }
void unodar_clear_onPressed() { count.set(0); }
void unodar_watch_0_callback(int32_t v) { Serial.println(v); }

// Delivery: first take every flag and value (declaration order), then run the observers. Locals carry the
// reserved unodar_ prefix, so they cannot shadow a user's signal (e.g. one named count_value).
void unodar_deliver() {
  const bool unodar_count_changed = count.take();
  const int32_t unodar_count_value = count.value();
  if (unodar_count_changed) isOdd.set(unodar_isOdd_compute());
  const bool unodar_isOdd_changed = isOdd.take();
  const bool unodar_isOdd_value = isOdd.value();
  if (unodar_count_changed) unodar_watch_0_callback(unodar_count_value);
  if (unodar_isOdd_changed) led.set(unodar_isOdd_value);
}

void setup() {
  Serial.begin(9600);
  led.begin();
  plus.begin();
  clear.begin();
  unodar_deliver();   // initial values (D5)
}

void loop() {
  if (plus.pressed()) unodar_plus_onPressed();
  if (clear.pressed()) unodar_clear_onPressed();
  unodar_deliver();
}
```

Runtime addition to `unodar_widgets.h` (one template; `Led::set` becomes public):

```cpp
template <typename T>
class Signal {
 public:
  constexpr explicit Signal(T initial) : value_(initial), changed_(true) {}  // starts changed: delivered at setup
  T value() const { return value_; }
  void set(T v) {               // a write of an equal value changes nothing (D4)
    if (v != value_) { value_ = v; changed_ = true; }
  }
  bool take() { const bool c = changed_; changed_ = false; return c; }
 private:
  T value_;
  bool changed_;
};
```

## 1. Syntax (D1)

**Recommendation.**

| Dart | Meaning | C++ |
|---|---|---|
| `final count = Signal<int>(0);` or `Signal(0)` | A signal: a top-level `final`, constant initial value | `unodar::Signal<int32_t> count(0);` |
| `count.value` | Read (any expression) | `count.value()` |
| `count.value = e;`, `+=`, `-=`, `++`, `--` | Write, statements only (as for variables) | `count.set(e);`, `count.set(count.value() + 1);` |
| `Watch(count, (v) { … })` | Runs the callback with the new value when `count` changes; a widget, listed in `children` | A generated `void unodar_watch_0_callback(int32_t v)` called from `unodar_deliver()` |
| `Led(pin: 13, on: flag)` | The LED follows a `Signal<bool>`/`Computed<bool>` (§6, D7) | `led.set(flag_value)` in `unodar_deliver()` |
| `led.set(b)` | Switch an LED to a bool (D7) | `led.set(b)` |
| `final c = Computed(() => expr);` | Derived value (§4, D6) | `unodar::Signal<T> c(…)` + `T unodar_c_compute()` |

`Signal<T>` and `Computed<T>` both implement `ReadonlySignal<T>` (`T get value`); `Watch<T>(ReadonlySignal<T>
signal, void Function(T value) callback)` is positional, like `Every(interval, callback)`. `T` is `int`, `double`,
`bool`, `Uint8`, `Uint16` or `Int16`.

Does it read like Flutter? `Signal`/`.value` is `ValueNotifier`/`.value` (and the `signals` package), with the
same equality rule (D4). `Watch` is the role of `ValueListenableBuilder`/`BlocListener`: an explicit listener on
one signal. `Led(on: flag)` is the core Flutter idea, an output described as a function of state.

**Alternatives and their cost.**
- Named `Watch(signal: count, onChange: (v) { … })`: more Flutter-like, but the one other callback widget,
  `Every`, is positional (PRD §7). Cost: two styles in one tree, or a breaking change to `Every`.
- Auto-tracked `Effect(() { … })` (the `signals` package): no explicit source, the compiler finds every `.value`
  read through the call graph. Cost: dependencies become invisible to the reader, a read in a rarely taken branch
  still subscribes, and the cycle check (E025) must explain inferred edges. Harder to explain, not more capable.
- A plain variable plus a `changed` flag the user checks by hand: no new API. Cost: none of the reactivity this
  phase is for.

## 2. Update model (D2)

**Recommendation: deferred delivery with a snapshot, once per `loop()` pass.** This is the maintainer's proposal,
made order-independent. A `loop()` pass has two phases:

1. **Inputs and timers**: poll every Button and Every in `children` order and run their callbacks (as in Phase 4).
   A write only stores the value and marks the signal changed (`set()`); it never runs other code.
2. **Delivery** (`unodar_deliver()`): first, for every signal in declaration order, take its changed flag and
   read its value (a `Computed` is re-evaluated here when a dependency changed, §4). Then, for every changed
   signal in declaration order, run its observers (Watches and bound Leds) in `children` order, each with the
   value taken in the first half.

Writes made during delivery (by a Watch callback) mark the signal again and are delivered in the **next** pass,
whichever signal is declared first. So:
- A press is seen by the Watches in the same pass.
- Each Watch runs at most once per pass, and every observer of a signal sees the same value in that pass.
- No callback ever runs inside another (no re-entrancy, no stack growth): `set()` calls nothing.
- Order is fixed by the source: declaration order for signals, `children` order for observers.
- With the cycle rule (E025, below), the graph "a Watch of A writes B" has no cycles, so after any input the
  program is quiet again after at most *L* + 1 passes, *L* the longest chain.

A Watch callback can still read other signals' `.value` directly; it then sees their current value, including a
write made earlier in the same delivery. That is plain state, like a top-level variable.

**What if a callback writes the signal it watches?** Rejected at compile time (E025), directly or through called
functions, and so is any longer cycle (`Watch(a)` writes `b`, `Watch(b)` writes `a`), with the path, like E016 and
E023. Under the deferred model such a program would not crash, but a watch that always writes a new value would
run on every pass for ever: a hidden busy loop the user did not write. Clamping belongs where the write starts
(`count.value = min(…)` in the Button callback) or in a `Computed`. This is D3.

| | Deferred, snapshot (recommended) | Synchronous (`set()` runs the watches at once) |
|---|---|---|
| Latency | Same pass for input writes; one pass per Watch→signal step (µs) | None |
| Writes in a loop (`for` 100 writes) | One delivery, final value | 100 callback runs (100 serial lines) |
| Intermediate values in one pass (0→1→0) | Coalesced: one delivery of the final value | Every value delivered |
| Re-entrancy, stack | None; depth fixed | Nested frames per chain step on a 2 KB stack; needs the same static cycle check to be bounded |
| Glitches (an observer sees A new, `Computed` of A old) | None: computeds settle before any observer runs | Possible mid-chain unless watches are topologically scheduled per write |
| Cost per write site | Compare + store + flag (inline) | A call into a generated per-signal function that runs every watch |
| RAM | 1 flag byte per signal | No flag; same values |
| Closest Flutter analogue | `setState` batching to the next frame | `ValueNotifier` listeners |

Synchronous propagation is what `ValueNotifier` does, but every Flutter developer also knows the frame model, and
only the deferred model is bounded without rejecting more programs.

## 3. Change detection and first value (D4, D5)

**D4 — equal writes do not notify.** `set()` compares (`!=`) and does nothing when equal, exactly
`ValueNotifier`'s rule (`if (_value == newValue) return;`). Doubles behave identically in C++ and Dart: writing
`NaN` always notifies (`NaN != NaN`), `-0.0` onto `0.0` does not and keeps `0.0`. Because writes within one pass
are coalesced, 0→1→0 in one callback still delivers `0` once (the signal was changed); documented in SUBSET.
Alternative: notify on every write. Cost: `count.value = 0` on a reset button prints `0` on every press, and a
`Computed` would need its own comparison anyway. Alternative: compare against the last delivered value (0→1→0
delivers nothing). Cost: a second copy of the value per signal (up to 4 B RAM each); kept for `Computed` only,
which has no stored current value.

**D5 — the initial value is delivered once, at the end of `setup()`**, after every widget's `begin()`
(signals start changed, and the generated `setup()` ends with `unodar_deliver()`). So a Watch prints the start
state and a bound Led shows it without extra code, as `ValueListenableBuilder` and `effect()` do. Writes made by a
Watch during that delivery arrive in the first `loop()` pass. Alternative: no initial delivery
(`addListener`-style). Cost: the user duplicates the "show the state" code for boot, and `Led(on:)` would start
in the wrong state for `Signal(true)`.

## 4. Derived values: `Computed` (D6, PRD §13.3)

**Recommendation: restricted expressions, in this phase, after a cut line** (steps 10–11; everything before them
stands alone if D6 defers it).

```dart
final isOdd = Computed(() => count.value % 2 == 1);
final level = Computed(() => raw.value * scale ~/ 100);   // scale is a const
```

- The body is a single `=>` expression of a supported type made of `.value` reads of signals and computeds
  declared **above**, constants, literals, and the operators the subset supports. No calls (not even to pure-looking
  functions or `analogRead`), no mutable top-level variables (the computed could not see them change), no
  assignments. Anything else is E026.
- **Cycles are impossible by construction**: a computed may only read nodes declared above it, so declaration
  order is a topological order, and the compiler re-evaluates in that order. No graph search, nothing to explain.
- **Reads always equal the expression**: `isOdd.value` in user code compiles to `unodar_isOdd_compute()`, so it
  is never stale, even in the middle of a delivery.
- **Delivery**: in the first half of `unodar_deliver()`, a computed with a changed dependency is re-evaluated and
  compared with the value it last delivered (stored in its `Signal<T>`, D4's alternative rule), so `isOdd` going
  0→2 notifies nothing. Observers then run as for signals: glitch-free, because every computed is settled first.
- A computed has no constant initial value of its own: it is stored as `T`'s zero and starts changed, so the
  setup delivery evaluates it.

Alternatives and their cost:
- **Defer to Phase 6.** Users write `final isOdd = Signal(false); Watch(count, (v) { isOdd.value = v % 2 == 1; })`.
  Cost: boilerplate per derived value, one extra pass of latency, a mutable signal that anyone can also write, and
  the Led sink (§6) is mostly used through that detour.
- **General closures** (`Computed(() { … })` with locals and calls to user functions). Cost: a purity analysis
  through the call graph (no writes, no hardware calls, no `cpp()`), and dependencies hidden in callees. That is
  the Phase 6+ version once restricted computeds prove insufficient; the restricted rule can only be relaxed later.

## 5. Memory and flash cost (measured in step 12)

Step 1 estimated these; step 12 measured them (arduino-cli 1.5.1, arduino:avr 1.8.8, `-fwrapv`, `-Os`, LTO). RAM per
object is exact: read per symbol with `avr-nm` and `static_assert`ed in `test/runtime/signals/signals.ino`. AVR has
1-byte alignment, so objects have no padding.

| Object | RAM (measured) |
|---|---|
| `Signal<int>`, `Signal<double>` | **5 B** (value 4 + mark 1) |
| `Signal<Uint16>`, `Signal<Int16>` | **3 B** |
| `Signal<bool>`, `Signal<Uint8>` | **2 B** |
| `Watch` | **0 B** (no symbol: a generated function and a branch) |
| `Led(on: …)` | **0 B** beyond the Led's own 2 B |
| `Computed<T>`, watched | **as `Signal<T>`** (its last delivered value and mark; `Computed<bool>` 2 B) |
| `Computed<T>`, not watched | **0 B** (the linker drops the object; reads call its compute function) |
| `unodar_deliver()` | **0 B** static (marks and values are locals) |

Flash depends on what the code around it does, so it was measured as the difference between programs that change
one construct each (a Led and a Button on D2, no Serial; Watch callbacks drive pins so nothing is optimized away):

| Variant | Flash | Difference, and what it includes |
|---|---|---|
| Reference: the press toggles a Led | 1186 B | — |
| One `Signal<bool>`, written by the press, one Watch | 1224 B | **+38 B**: the signal's write, the Watch, `unodar_deliver()` with one take/branch |
| The same with a bound Led instead of the Watch | 1252 B | +28 B over the Watch, mostly the extra Led object's `begin()` |
| One `Signal<int>` (`count.value++`), Watch `led.set(v % 2 == 1)` | 1430 B | +244 B, most of it the 32-bit `%` (`unodar_mod`, avr-libc's 32-bit division) |
| …plus a second Watch of the same signal | 1486 B | **+56 B** per extra Watch (with its own comparison) |
| …plus a second watched `Signal<int>` | 1564 B | **+78 B** per extra watched signal (its write, take, value, branch) |
| …plus a second write site (`count.value = count.value * 3`) | 1526 B | +96 B over one write, including a 32-bit multiply |
| Watching `Computed(() => count.value % 2 == 1)` instead of `count` | 1464 B | **+34 B** for the re-evaluation in delivery; +2 B RAM for its object |

So the delivery machinery itself costs tens of bytes; what dominates is the arithmetic the program asks for, as
everywhere on AVR. The goal program (`examples/counter`, step 13) measures **2894 B flash and 210 B RAM** (Serial
175 + core 9 + count 5 + isOdd 2 + Led 2 + two Buttons 14 + 3 B), against the step-1 estimate of about 3000-3100 B
and 215 B. Packing the marks into bit
fields would save at most 7 bits per signal at the cost of bit operations at every write and take; not worth it
below dozens of signals.

## 6. Interaction with Phase 4 (D7)

- **Widgets as sinks (D7)**: `Led(pin: 13, on: flag)` with a `Signal<bool>` or `Computed<bool>`. The LED is driven
  only by the signal: at setup (D5) and whenever it changes. Calling `on()`/`off()`/`toggle()`/`set()` on a bound
  Led is E022 (two writers would fight; the signal is the single source of truth). An unbound Led gets a public
  `set(bool)` (the runtime already has it, private), which the maintainer's example uses. Other sinks (an Every
  interval, a Button as a `Signal<bool>` source) are out of scope.
- **E021** (program shape): `Signal`, `Watch`, `Computed` in a `setup()`/`loop()` sketch are E021, like widgets;
  delivery only exists in the generated `loop()`, so a signal there would silently never notify.
- **E022** (widget rules): `Watch` is a widget: a top-level `final` or inline in `children`, listed exactly once,
  and its callback may use only widgets declared above it. A signal is **not** a widget and is not listed in
  `children` (a Dart type error, E007, since `children` is `List<Widget>`). The signal argument of a widget (Watch
  source, Led `on:`) must be declared above it (E015 forward reference, as for constant widget arguments).
  Callback bodies may read and write any signal, whatever its position (callbacks are emitted after all globals).
- **E023**: Watch callbacks are widget callbacks, so `delay()` in them is rejected, directly or indirectly.
- **E012**: a Watch callback takes exactly one parameter, the value (the analyzer enforces its type, E007); the
  other closure rules of Phase 4 apply. A computed's closure is the one other new closure position.
- **E013**: a `.value` read counts as a read of mutable top-level state (`next() + count.value` is E013).
- **E015**: the initial value is a compile-time constant (`Signal(analogRead(A0))` is E015), the bound-object rule.
- **E009**: `Signal<String>`, `Signal<num>`, `Signal<int?>`, `Signal<Servo>` are E009 (unsupported type).

## 7. New diagnostics (next free: E024)

| Code | Rule | One-line example → message | Help |
|---|---|---|---|
| E024 | Signal misuse: a signal that is not a top-level `final` initialized by `Signal(…)` (`var`, local, in a callback); a signal used as a value (stored, compared, passed, printed, returned); a parameter, local or return type of a signal type; a Watch source that is not the name of a top-level signal | `Serial.println(count);` → "the signal 'count' can only be read or written through `.value`." | "Write `count.value`." / "Declare signals at the top level: `final count = Signal<int>(0);`." |
| E025 | Reactive cycle: a Watch callback writes, directly or through called functions, the signal it watches or a signal whose Watches lead back to it; reported once per cycle with the path | `Watch(count, (v) { count.value = v + 1; })` → "the Watch of 'count' writes 'count' (Watch(count) → count), so it would run again on every pass." | "Write the signal where the change starts, e.g. in the Button callback, or derive the value with `Computed`." |
| E026 | `Computed` rules (only if D6 includes it): a block body, a call, an assignment, a read of a mutable top-level variable, or a read of a signal or computed declared below | `Computed(() => count.value + offset)` with `int offset` → "a Computed can only read signals and computeds declared above it and constants; 'offset' is a mutable variable, so its changes would not be seen." | "Make 'offset' a Signal or a `const`." |

Existing codes gain cases (wording only): E009 (signal type arguments), E013 (`.value` reads), E015 (initial
values, signal arguments declared below), E021 (signals in sketches), E022 (Watch as a widget, bound Led methods).
Each problem is reported once, under the family a user searches by.

## 8. Steps (one construct per commit, test first)

Steps 5–9 also deleted their construct's snippet from `test/unit/pending_constructs_test.dart`, which checked that
everything declared in step 3 but not yet compiled was rejected with diagnostics, never an internal error; the file
was deleted with step 9, when the list became empty. Every
construct step adds positive and negative goldens first; each positive golden is compiled by arduino-cli,
gets its first-measurement size budget in the same commit, and passes the no-heap (`avr-nm`) check; each construct
gets an avr8js behaviour test with a negative control in the same commit (not in a later step, as in Phase 4).

| # | Step | Test written first |
|---|---|---|
| 1 | This plan and the decisions (**done**, 1979f7a) | — |
| 2 | (**done**) Spec, after the maintainer's answers: SUBSET "Signals" (syntax, pass model, timing, costs, deviations), DIAGNOSTICS E024–E026 and the reworded codes (`docs_test` runs a section's example once its code is registered, so the new sections carry their final examples; no existing example changes, so no `docs/drafts` file), PRD status and §13.3 | `docs_test` stays green |
| 3 | (**done**) `packages/unodar`: `ReadonlySignal<T>`, `Signal<T>`, `Watch<T>`, `Led.set`, `Led(on:)` (`Computed` waits for step 10) | `api_surface_test` |
| 4 | (**done**) `runtime/unodar_widgets.h`: `unodar::Signal<T>`, public `Led::set`; re-embed | avr8js runtime sketch: sizes (`static_assert` 5/3/2 B), equal write silent, NaN notifies, take clears, coalescing, a hand-written two-phase delivery with snapshot (a write during delivery waits a pass); negative controls: `set()` without the compare, delivery without the snapshot; header-equality test |
| 5 | (**done**) Signal declarations, `.value` reads and writes (no Watch yet): E024 (placement, value uses, types of locals/parameters), E009, E015, E021, E013 | Goldens `signal_state` + negatives; avr8js: presses increment, an `Every` prints the count, a `Signal<Int16>` read stays 32-bit in `* 1000`; control: that read emitted without the widening |
| 6 | (**done**) `Watch` and delivery: `unodar_deliver()` (emitted only when observed), setup delivery, snapshot, ordering; Watch as a widget (E022), source argument (E024), callback rules (E012, E023) | Goldens `watch`, `watch_order` + negatives; avr8js: initial value printed once, equal write silent, two writes in one callback delivered once, declaration/children order; control: delivery without snapshot |
| 7 | (**done**) E025 cycle check: write edges from Watch callbacks through the call graph (shared with E016/E023), path in the message | Goldens `e025_self_write`, `e025_cycle`, `e025_indirect`; positive `watch_chain` (A→B→C); avr8js: one press prints A, B, C once each, in order |
| 8 | (**done**) `Led.set(bool)` on unbound Leds | Golden `led_set` (replaces the interim `e003_widget_method`); avr8js pin log |
| 9 | (**done**) `Led(on: signal)` sink; E022 for methods on a bound Led; signal argument declared below (E015) | Golden `led_sink` + negatives; avr8js: pin 13 follows the signal from boot (initial `true` lights it at setup) |
| — | **Cut line**: steps 10–11 only if D6 includes `Computed` | |
| 10 | (**done**) `Computed<T>` declaration and reads (pull: `unodar_c_compute()`); E026 | Goldens `computed` + `e026_*`; avr8js: reads equal the expression right after a write |
| 11 | (**done**) Computed in delivery: re-evaluate on changed dependencies, compare with last delivered, Watch and `Led(on:)` on a computed | Golden `computed_watch`; avr8js: 0→2 notifies nothing, observers never see a stale computed; control: delivery that runs observers before re-evaluating |
| 12 | (**done**) Size-budget review (dedicated commit): every Phase 5 budget, RAM per signal golden, the §5 estimates replaced by measurements | `size_budgets.dart` |
| 13 | (**done**) `examples/counter` (the goal program) with `wokwi/` (two buttons, the L LED, serial monitor), built by `tool/check_arduino.sh` | avr8js on the goal program: bounced presses on D2 and D3, exact serial transcript (`0`, `1`, `2`, `0`; clear at 0 prints nothing) and pin-13 log; negative control |
| 14 | (**done**) Final docs pass (README status and known limits, PRD status, PLAN); full check suite; end report | — |

## 9. Decisions (approved by the maintainer on 2026-11-14, all as recommended)

| # | Decision | Recommendation | Cost of the alternative |
|---|---|---|---|
| D1 | Syntax | `Signal<T>(initial)`, `.value` get/set (incl. `++`, `+=`), `Watch(signal, (v) { … })` positional, listed in `children` | Named `Watch(signal:, onChange:)`: differs from `Every`. Auto-tracked `Effect`: hidden dependencies, harder errors |
| D2 | Update model | Deferred: writes mark changed; one delivery per pass at the end of `loop()`, flags and values snapshotted first; writes during delivery arrive next pass | Synchronous: re-entrant nested calls on a 2 KB stack, 100 writes run 100 callbacks, glitches unless scheduled per write |
| D3 | A Watch writing the signal it watches, and longer cycles | Rejected at compile time (E025), with the path | Allowed and delivered next pass: a watch that always writes a new value silently runs on every pass for ever |
| D4 | Equal writes | Do not notify (`ValueNotifier` rule); one-pass coalescing, so 0→1→0 delivers `0` once | Notify on every write: a reset at 0 still prints. Compare with last delivered: +sizeof(T) RAM per signal |
| D5 | First value | Delivered once at the end of `setup()` | Not delivered: boot-state code duplicated by hand; `Led(on: Signal(true))` starts wrong |
| D6 | `Computed` (PRD §13.3) | Restricted single expressions over signals/computeds declared above and constants, in Phase 5 after the cut line; pull reads; cycles impossible by declaration order | Defer: hand-written mirror signal + Watch per derived value, +1 pass latency. General closures: purity analysis, hidden dependencies |
| D7 | Widgets as sinks | `Led(on: ReadonlySignal<bool>)` only; methods on a bound Led rejected (E022); public `Led.set(bool)` for unbound Leds | No sinks this phase: every output needs a Watch; or more sinks now (Every interval, Button as a source): more runtime and rules before the basic model is proven |

## Extension hooks kept

- Signals lower into existing IR (`IrBoundObject` of `unodar::Signal<T>`, receiver calls, `IrIf`, `const` locals),
  so no parallel code path; delivery is one generated `IrFunction`.
- The write-edge graph for E025 extends the call graph that E016 and E023 already build.
- Sinks are registry data (which widget parameter takes a `ReadonlySignal<bool>`, which runtime method it calls),
  so Phase 8 display widgets (`Text('${count.value}')`) can become sinks without a new mechanism.
- `ReadonlySignal<T>` leaves room for future sources (a Button's state, a sensor) behind the same interface.

---

# Phase 4 plan — static widget tree

**Status: done (2026-11-13), tagged v0.4.0.** Approved by the maintainer and built step by step. Step 6 ran in the
order a, f, b, c, d, e (Serial auto-begin before callbacks; see DECISIONS).

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
