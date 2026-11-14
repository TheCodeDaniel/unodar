# Unodar Dart subset — Phase 5 (signals, in progress; experimental)

This is the **exact** list of what the compiler accepts. Anything not listed here is rejected with a diagnostic
(see [`DIAGNOSTICS.md`](DIAGNOSTICS.md)). The subset grows phase by phase; this file is updated *before* any new
syntax is accepted.

**Fidelity rule.** Generated C++ behaves exactly like the Dart source, or the construct is rejected. The only
exceptions are listed under [Known deviations from Dart](#known-deviations-from-dart); each one is a deliberate,
documented decision (see `DECISIONS.md`). Raw C++ written with the [escape hatch](#escape-hatch-cpp-and-cppinclude)
is outside this rule: unodar copies it, it does not check what it means.

**No heap.** Generated code never allocates memory at runtime: no `new`, `malloc`, or Arduino `String`. Strings are
literals stored in flash, and C++ objects are global variables, allocated statically.

## A complete valid program

```dart
import 'package:unodar/unodar.dart';

const int sensorPin = A0;
final servo = Servo();
int lastReport = 0;

void setup() {
  Serial.begin(9600);
  pinMode(LED_BUILTIN, OUTPUT);
  servo.attach(9, min: 600, max: 2400);
}

void loop() {
  final level = analogRead(sensorPin);
  servo.write(level * 180 ~/ 1023);
  analogWrite(6, level ~/ 4);
  final now = millis();
  if (now - lastReport >= 1000) {
    lastReport = now;
    Serial.print('level=');
    Serial.println(level);
    Serial.println(level / 1023 * 5.0, digits: 3);
    Serial.println(digitalRead(2) == HIGH);
  }
}
```

## Types

| Dart | C++ | Notes |
|---|---|---|
| `int` | `int32_t` | 32-bit, not Dart's 64-bit. See [deviations](#known-deviations-from-dart). |
| `double` | `float` | 32-bit IEEE float, not Dart's 64-bit double. On the Uno, C++ `double` is also 32-bit. |
| `bool` | `bool` | |
| `Uint8` | `uint8_t` | From `package:unodar`. 0 to 255. |
| `Uint16` | `uint16_t` | From `package:unodar`. 0 to 65535. |
| `Int16` | `int16_t` | From `package:unodar`. -32768 to 32767. |
| `void` | `void` | Function return type only. |
| String literal | `F("…")` | **Only** as the argument of `Serial.print`/`Serial.println` (see [Serial](#serial)). |
| A [binding class](#binding-c-classes) | its `@CppClass` name | **Only** as the type of a top-level `final` object (E018). |
| `Signal<T>`, `Computed<T>` | `unodar::Signal<…>` | **Only** as a top-level `final` signal, see [Signals](#signals) (E024). `T` is one of the types above it. |

Every other type is rejected (E009), including nullable types (`int?`), `num`, `dynamic`, `Object`, `String`
(as the type of a variable, parameter, or return value), function types, and classes. That includes the *inferred*
static type of an expression: `flag ? 1 : 2.5` has type `num` in Dart and is rejected.

### Sized integers (`Uint8`, `Uint16`, `Int16`)

These are Dart extension types over `int` (`implements int`). Their Dart behaviour is real, executable Dart, and the
C++ behaves identically:

- **Create** one with its constructor: `Uint8(x)`. The value wraps into range exactly like the C++ conversion:
  `Uint8(300) == 44`, `Uint16(-1) == 65535`, `Int16(40000) == -25536`. Emitted as `uint8_t(x)` etc.
- **Read** one anywhere an `int` is expected; reading widens losslessly.
- **Arithmetic** on sized values produces an `int` (`Uint8 + Uint8` is an `int`, computed in `int32_t`).
- **Store back** with an explicit constructor: `level = Uint8(level + 1);`. `Uint8 x = 300;` and `x++` on a `Uint8`
  are Dart type errors (E007), so a value is never truncated without a visible `Uint8(...)`.

## Top-level declarations

| Construct | Rule | C++ |
|---|---|---|
| `void setup()`, `void loop()` | Both required in a sketch without `main()`. Exactly `void name() { … }` (E006). | Same |
| `void main()` | Only as the single `runDevice(Device(…))` call of a widget program, see [Widgets](#widgets-rundevice); then `setup()`/`loop()` are not allowed (E021). | Generated `setup()` and `loop()` |
| Widgets | `final led = Led(pin: 13);`, `final button = Button(pin: 2, onPressed: () { … });`, or written directly inside `Device(children: […])`. Arguments are compile-time constants (E022). | `unodar::Led led(13);` and so on, from `unodar_widgets.h` |
| Signals | `final count = Signal<int>(0);`, `final isOdd = Computed(() => …);` in a widget program, see [Signals](#signals). | `unodar::Signal<int32_t> count(0);` |
| Functions | `R name(T a, T b) { … }` or `=> expr;`. `R` is a supported type or `void`; every parameter is required, positional, and has an explicit supported type. Recursion, direct or mutual, is rejected (E016). | Same, plus a prototype for each function |
| `const` variables | `const int x = …;` or `const x = …;` (type inferred). | `constexpr int32_t x = …;` |
| `final` variables | As above with `final`. | `const int32_t x = …;` |
| Mutable variables | `int x = …;` or `var x = …;`. | `int32_t x = …;` |
| Binding classes | A class annotated `@CppClass`, see [Binding C++ classes](#binding-c-classes). | Nothing (it names an existing C++ class) |
| Bound objects | `final servo = Servo();`, constructor arguments compile-time constants (E015). | `Servo servo;`, `SoftwareSerial link(10, 11);` |
| External objects | `external final TwoWire Wire;`, an existing C++ object of a binding class. | Nothing (it names an existing C++ object) |
| `@CppInclude('Foo.h') library;` | Extra headers, see [Escape hatch](#escape-hatch-cpp-and-cppinclude). | `#include <Foo.h>` |

**Top-level initializers** are required and must be compile-time constant expressions (E015): literals, unodar
constants (`HIGH`, `A0`, …), `const` variables declared **above** this one, `Uint8(…)`/`Uint16(…)`/`Int16(…)` of
constants, and the operators below. A `final` or mutable variable is not a constant, even if its initializer is.
The arguments of a bound object's constructor follow the same rule.

Still rejected: `main()` of any other shape (E008); classes without `@CppClass`, enums, mixins, extensions, typedefs, top-level
getters/setters (E005); `late` variables, and `external` variables whose type is not a binding class (E005);
optional, named, or default parameters, type parameters, `async`/generators, `external` functions, untyped
parameters (E011).

## Statements

Allowed inside any function body:

| Statement | Notes |
|---|---|
| Call | `pulse(300);`, `delay(ms);`, `servo.write(90);`. A non-void result may be discarded. |
| Assignment | `x = e;`, `x += e;`, `x -= e;`, `x++;`, `x--;`, `++x;`, `--x;`, and the same on a signal's `.value` (`count.value++;`, see [Signals](#signals)). **Statements only**: an assignment, `++`, or `--` inside a larger expression is rejected (E002). `*=`, `/=`, `~/=`, `%=` and the bitwise forms are rejected (E002); write `x = x * y;`. |
| Local variable | `int x = e;`, `var x = e;`, `final x = e;`, `const x = e;`, `int x;`. Any initializer expression. Types are the resolved Dart types. `const` → `constexpr`, `final` → `const`. `late` is rejected. |
| `if` / `else` | Including `else if` chains. |
| `while` | |
| `for` | C-style: `for (init; condition; updates)`, each part optional. Updates follow the assignment rule. |
| `return` | `return;` or `return e;`. |
| `break`, `continue` | Unlabeled only. |
| Nested block | `{ … }` |
| Raw C++ | `cpp('…');` as a statement of its own, see [Escape hatch](#escape-hatch-cpp-and-cppinclude). |

Rejected (E002): `do`/`while`, `switch`, `for`-`in`, labeled statements and labeled `break`/`continue`, `try`,
`throw`, `assert`, `yield`, empty statements (`;`), pattern declarations, `late` locals, a `for` that declares more
than one variable, and expression statements that are not a call or an assignment (`x + 1;`). Local functions are
E012. A rejected statement is reported as a whole; the code inside it is checked once it has been rewritten.

## Expressions

| Construct | Rule | C++ |
|---|---|---|
| Integer literals | Decimal or hex, at most 2147483647 (E010). Write `-2147483647 - 1` for the minimum. | Decimal, plus an `L` suffix only where needed (see below) |
| Double literals | At most the `float` maximum (≈3.4e38, E010). An integer literal in a `double` context (`double d = 1;`) is a double. | `1.0f`, `3.5f`, `1e-7f` |
| Bool literals | `true`, `false` | Same |
| String literals | Only as the argument of `Serial.print`/`Serial.println`. No interpolation (E002). | `F("…")` |
| Names | Locals, parameters, top-level variables, unodar constants. | Same name |
| Signal reads | `count.value`, `isOdd.value` (see [Signals](#signals)) | `count.value()`, `unodar_isOdd_compute()` |
| Parentheses | Kept where C++ needs them; see Precedence. | |
| Unary | `-x`, `!b` | Same |
| Arithmetic | `+`, `-`, `*` on numbers. | Same |
| `~/` | Integer division, truncating toward zero. `int` operands only. | `/` (also truncates toward zero) |
| `/` | On ints or doubles; the result is a `double`, as in Dart. | `float(a) / float(b)` for ints |
| `%` | `int` operands only. **Dart semantics**: the result is never negative (`-7 % 2 == 1`), including for the divisor -2147483648. | `unodar_mod(a, b)`, a one-line `constexpr` helper emitted only when used |
| Comparison | `==`, `!=`, `<`, `<=`, `>`, `>=`. Both sides numbers, or (for `==`/`!=`) both bools; anything else is E009, because `true == 1` is false in Dart and true in C++. | Same |
| Logical | `&&`, `\|\|` (short-circuit) | Same |
| Conditional | `c ? a : b`, where the result has a supported type. | Same |
| Calls | Functions declared in this file, and unodar API functions. | Same |
| Method calls | On `Serial`, on a bound object, or on an external object: `servo.write(90)`, `Wire.read()`. | `servo.write(90)` |
| Named arguments | Only where the API or binding declares named parameters, e.g. `servo.attach(9, min: 600)`. | Passed positionally, in declaration order; an omitted one gets its declared default |
| Sized constructors | `Uint8(e)`, `Uint16(e)`, `Int16(e)` | `uint8_t(e)` etc. |

Rejected: `%` and `~/` on doubles, bitwise and shift operators (`& | ^ ~ << >> >>>`), `??`, `is`/`as`, method and
property access on numbers such as `x.abs()` or `x.isEven` (E003 / E002), string literals anywhere except a Serial
argument, string interpolation, `null`, collection literals, cascades, `throw`, `await` (E002); using a bound object
other than to call one of its methods (E018); closures and function references such as passing `pulse` without
calling it (E012).

### Integer arithmetic is always 32-bit

On the Uno, C++ `int` is 16 bits, so plain C++ `60 * 1000` wraps to -5536. Unodar guarantees that every `int`
operation is computed in `int32_t`: when *both* operands would otherwise be narrower in C++, the emitter widens one
of them, with an `L` suffix on a literal (`60L * 1000`) or `int32_t(x)` otherwise (e.g. two `Uint16` values).
Comparisons get the same treatment where C++ would otherwise compare a `Uint16` (C++ `unsigned int` on the Uno)
with a signed value as *unsigned*: in plain C++, `Uint16(1) < -1` is true.

The same holds for the results of Arduino functions: `analogRead` returns a 16-bit C++ `int`, so
`analogRead(A0) * 100` is emitted as `analogRead(A0) * 100L` and `analogRead(A0) * scale` as
`int32_t(analogRead(A0)) * scale` when `scale` is narrow too. `millis()` and `micros()` return C++
`unsigned long` and are emitted as `int32_t(millis())`, so they compare and subtract as Dart `int`s. Because
sketches are built with `-fwrapv` (see [Building](#building)), the usual timer check `now - last >= interval` stays
correct when the counter wraps.

### Constant expressions are checked

Any subexpression made only of constants (literals, unodar constants, `const` variables) is evaluated at compile
time with Dart semantics. If any intermediate value leaves the `int32_t` range, or it divides by zero with `~/`,
`%`, or `/`, it is rejected (E010). So is `-2147483648 % -1`, which C++ cannot compute. `delay(60 * 60 * 1000 * 1000)` is an error, not a silent wrap.

### Precedence

The C++ is printed from the expression tree that Dart parsed, with parentheses inserted wherever C++ precedence or
associativity would otherwise regroup it: `a - (b - c)` keeps its parentheses, `(a + b) * c` keeps them,
`- -x` is never printed as `--x`. Redundant parentheses may be dropped.

### Evaluation order

Dart evaluates operands and arguments strictly left to right. C++ does not fix the order for the operands of most
operators or for call arguments. So where the order could matter, unodar rejects the code (E013): within one
operator's operands, one call's argument list, or the two sides of `+=`/`-=`,

- two calls may not sit next to each other. This covers every kind of call: your functions, Arduino functions
  (`micros() - micros()`, `analogRead(A0) - analogRead(A1)`), and methods (`Wire.read() + Wire.read()`);
- a call to one of your functions may not sit next to a read of a mutable top-level variable (the call might change
  it).

A call *inside* another call's argument (`Serial.println(analogRead(A0))`) is fine: the inner call always runs
first. `&&`, `||`, and `?:` are always fine. Fix: store a call's result in a local variable first.

## Names

User declarations (top-level variables, functions, parameters, locals, bound objects) may not use a name that would
collide with C++ or the Arduino core (E014):

- C++ keywords, including the alternative operator names that are valid Dart identifiers (`and`, `or`, `not`, …).
- Every unodar API name (`pinMode`, `analogRead`, `Serial`, `HIGH`, …), taken from the compiler's API registry,
  and the C++ class and object names of every binding (`Servo`, `TwoWire`, `Wire`, …).
- Every lower- or mixed-case name that `#include <Arduino.h>` defines on the Uno: macros (`min`, `max`, `abs`,
  `round`, `sq`, `constrain`, `bit`, …), typedefs (`byte`, `word`, `u8`, …), functions (`init`, `map`, `millis`,
  `square`, `sqrt`, …), classes, and objects (`Serial`). The list (`UnoTarget.reservedNames`, ~600 names) is
  generated from the real headers by `tool/extract_arduino_names.sh`, and a test re-checks it against the
  installed core.
- ALL-CAPS names (no lower-case letter): the AVR headers define hundreds of macros such as `PORTB`. Dart style
  already prefers `ledPin` over `LED_PIN`.
- Names ending in `_t`, containing `__` or `$`, starting with `_` and an upper-case letter, or starting with
  `unodar_` (reserved for generated helpers, widgets written inside `children`, and callbacks).
- `unodar`, the C++ namespace of the widget runtime, and the widget and signal names `Led`, `Button`, `Every`,
  `Watch`, `Device`, `Uno`, `runDevice`, `Signal`, `Computed`, `ReadonlySignal` (unodar API names).
- A top-level widget name whose callback would get the same C++ name as that of a widget written in `children`:
  `final button_0 = Button(…)` next to an inline `Button` (both callbacks would be `unodar_button_0_onPressed`).
  Write `button0` instead; Dart style already prefers it.

The Dart names of binding classes and their methods are not emitted (the C++ names come from the annotations), so
they are not checked.

## Recursion

A function may not call itself, directly (`f` calls `f`) or through other functions (`ping` calls `pong` calls
`ping`), E016. The compiler builds the call graph of all user functions, including `setup` and `loop`, and rejects
every cycle. Reason: the Uno has a 2 KB stack and no overflow check, so where Dart throws `StackOverflowError`,
the board would silently overwrite its global variables. Rewrite recursion as a loop.

## Calling the unodar API

| Function | Arduino C++ parameters | Result |
|---|---|---|
| `pinMode(pin, mode)` | `uint8_t pin, uint8_t mode` | `void` |
| `digitalWrite(pin, value)` | `uint8_t pin, uint8_t val` | `void` |
| `digitalRead(pin)` | `uint8_t pin` | `int`: `HIGH` or `LOW` (C++ `int`) |
| `analogRead(pin)` | `uint8_t pin` | `int`: 0 to 1023 (C++ `int`) |
| `analogWrite(pin, value)` | `uint8_t pin, int val` | `void`. Duty cycle 0 to 255 on PWM pins. |
| `delay(ms)` | `unsigned long ms` | `void` |
| `millis()` | | `int`: milliseconds since reset (C++ `unsigned long`, emitted as `int32_t(millis())`) |
| `micros()` | | `int`: microseconds since reset (likewise `int32_t(micros())`) |

| Constant | Value on the Uno | Use |
|---|---|---|
| `HIGH`, `LOW` | 1, 0 | Digital levels |
| `INPUT`, `OUTPUT`, `INPUT_PULLUP` | 0, 1, 2 | Pin modes |
| `A0` … `A5` | 14 … 19 | Analog input pins (also usable as digital pins) |
| `LED_BUILTIN` | 13 | The on-board LED |

Arguments may be any supported `int` expression. A **constant** argument outside the Arduino parameter's range is
rejected (E004), e.g. `digitalWrite(-13, HIGH)` or `analogWrite(3, 40000)`. Non-constant values are converted to
the Arduino parameter type (see deviations). The constants are ordinary `int` constants usable in any expression
and emitted by name (`A0`, not `14`).

### Serial

`Serial` is the Uno's hardware serial port (C++ `Serial`, a `HardwareSerial`).

| Dart | C++ | Notes |
|---|---|---|
| `Serial.begin(baud)` | `Serial.begin(baud)` | `unsigned long baud`, e.g. 9600 |
| `Serial.print('text')` | `Serial.print(F("text"))` | A string **literal**: stored in flash, never copied to RAM. |
| `Serial.print(n)` | `Serial.print(n)` | `int`, `Uint8`, `Uint16`, `Int16`: decimal, as Dart's `toString()` |
| `Serial.print(b)` | `Serial.print(b ? F("true") : F("false"))` | `bool`: `true`/`false`, as Dart's `toString()` (Arduino alone would print `1`/`0`) |
| `Serial.print(x)`, `Serial.print(x, digits: 3)` | `Serial.print(x, 2)`, `Serial.print(x, 3)` | `double`: **Arduino's** fixed-point format with `digits` decimals (default 2), so `1.5` prints `1.50`. See deviations. |
| `Serial.println(…)` | `Serial.println(…)` | As `print`, then a line break (`\r\n`). |
| `Serial.println('')` | `Serial.println()` | An empty line. (`Serial.println()` with no argument is a Dart error, E007: Dart has no overloading, and a method cannot have both an optional positional and a named parameter.) |

A string literal may use any Dart escape (`\n`, `\t`, `\u{…}`) and may be raw (`r'…'`) or adjacent literals
(`'a' 'b'`); interpolation (`'$x'`) is E002 (print the parts with separate calls), and a NUL character (`\x00`) is
E002 (it would end the C string). Non-ASCII characters are sent as their UTF-8 bytes. `digits:` is only accepted
with a `double` value (E004), and a constant `digits` must be 0 to 255 (E004). Any other argument type, including
a `String` variable, is E009.

### Named arguments

An API function or binding method may declare named parameters with default values. Unodar passes every parameter
to C++ positionally, in declaration order; an omitted named argument gets its declared default. So
`servo.attach(9)` compiles to `servo.attach(9, 544, 2400)`, which is what the C++ `attach(9)` does too. A named
argument the declaration does not have is a Dart error (E007).

## Binding C++ classes

A binding is a Dart class that describes an existing C++ class, so that Dart code can call it. It compiles to
direct C++ calls: there is no wrapper and no runtime. Unodar ships two (below); you can write your own in your
program file, typically in about ten lines.

```dart
@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppType('uint8_t') int rx, @CppType('uint8_t') int tx);
  external void begin(@CppType('long') int baud);
  @CppName('write')
  @CppType('size_t')
  external int writeByte(@CppType('uint8_t') int value);
}

final link = SoftSerial(10, 11); // C++: SoftwareSerial link(10, 11);
```

Rules (E017 for any violation):

- `@CppClass('Name')` is required and names the C++ class (`ns::Name` is allowed). `@CppHeader('File.h')` names the
  header that declares it; omit it only for classes that `Arduino.h` already declares.
- The class has no `extends`, `implements`, `with`, or type parameters, and only these members: at most one
  unnamed `external` constructor, and `external` instance methods. No fields, getters, setters, operators, static
  members, or members with a body. A class that C++ code only reaches through existing objects (like `TwoWire`,
  reached through `Wire`) is declared `abstract` and has no constructor.
- Parameters and return types use the supported types. Parameters are required positional, or named with a constant
  default value (`{int min = 544}`) or `required`. No optional positional parameters.
- `@CppName('name')` on a method gives its C++ name. Use it for **overloads**: Dart has no overloading, so give each
  C++ overload its own Dart name (`writeByte`, `writeLong`) and map them all to `write`.
- `@CppType('uint8_t')` on a parameter gives its exact C++ type. Unodar then range-checks constant arguments
  against it (E004) and converts other arguments explicitly (`uint8_t(x)`), which also picks the right C++ overload.
  On a method it gives the C++ return type, which unodar needs to keep `int` arithmetic 32-bit. Accepted types:
  `bool`, `float`, `double`, `int8_t`, `uint8_t`, `int16_t`, `uint16_t`, `int32_t`, `uint32_t`, `int`,
  `unsigned int`, `long`, `unsigned long`, `size_t`. An integer method without `@CppType` is emitted as
  `int32_t(obj.method(…))`.
- `@CppRange(min, max)` on an integer parameter narrows the range of its C++ type to the values the library
  actually handles, e.g. `{@CppType('int') @CppRange(33, 1059) int min = 544}` on `Servo.attach`. Constant
  arguments outside it are E004, like those outside the C++ type. Both bounds are integer literals within the C++
  type's range, and `min <= max`. It does not change the C++ type or the conversion; non-constant values are not
  checked (see deviations).
- C++ names must be valid C++ identifiers, and header names plain file paths (`Wire.h`, `utility/twi.h`).

**Using a binding** (E018 otherwise): a bound object is a top-level `final` variable initialized by its
constructor, with compile-time-constant arguments (E015); it becomes a C++ global, so it is allocated statically and
constructed before `setup()` runs. An existing C++ object is declared `external final TwoWire Wire;` (its C++ name
is the Dart name, or `@CppName('…')`). The only thing you can do with either is call its methods: no locals,
parameters, or return values of a binding type, no assignment, no comparison, and no passing it as an argument.
Each `@CppHeader` of a binding your program uses is included once.

### Wire (I²C), ships with the AVR core

```dart
Wire.begin();
Wire.beginTransmission(0x68);
Wire.write(0x6B);
Wire.write(0);
final status = Wire.endTransmission();
Wire.requestFrom(0x68, 2);
final high = Wire.read();
```

| Dart (`Wire`, a `TwoWire`) | C++ |
|---|---|
| `begin()`, `setClock(hz)` | `Wire.begin()`, `Wire.setClock(uint32_t)` |
| `beginTransmission(address)` | `uint8_t address` |
| `write(value)` → `int` | `Wire.write(uint8_t)`, returns bytes written |
| `endTransmission()` → `int` | 0 on success, else an error code |
| `requestFrom(address, quantity)` → `int` | `Wire.requestFrom(int, int)`, returns bytes received |
| `available()` → `int`, `read()` → `int` | `read()` is -1 when nothing is buffered |

### Servo, from the Arduino library index

Servo is **not** part of the AVR core: install it once with `arduino-cli lib install Servo` (unodar is tested with
Servo 1.3.0). `tool/check_arduino.sh` and the `arduino`-tagged tests fail with that instruction when it is missing.

| Dart (`Servo`) | C++ |
|---|---|
| `final servo = Servo();` | `Servo servo;` |
| `attach(pin, {min = 544, max = 2400})` → `int` | `servo.attach(int, int, int)`; pulse widths in µs. The library stores them as `int8_t` offsets in 4 µs steps from 544 and 2400, so only `min` 33…1059 and `max` 1889…2915 work; constants outside are E004 (`@CppRange`). |
| `write(angle)`, `writeMicroseconds(us)` | `int` parameters |
| `read()` → `int`, `readMicroseconds()` → `int` | |
| `attached()` → `bool`, `detach()` | |

### Libraries reserve RAM

The Uno has 2048 bytes of RAM, and the objects of each library you use take part of it before your own variables
do: `Serial` keeps a 64-byte receive and a 64-byte transmit buffer, `Wire` a set of 32-byte buffers, a
`SoftwareSerial` a 64-byte receive buffer (shared by all its objects), and Servo a table for every servo it can drive. A test
program using `Serial`, `Wire`, a `SoftwareSerial` object and a `Servo` object together uses **544 B of the 2048 B**
before any `loop()` locals. This is static allocation (arduino-cli reports it as "Global variables use …"), so it is
fixed and visible at build time; leave room for the stack. The size budgets record RAM for every binding golden.

## Escape hatch: `cpp()` and `@CppInclude`

For anything not wrapped yet:

```dart
@CppInclude('avr/wdt.h')
library;

import 'package:unodar/unodar.dart';

void setup() {
  cpp('wdt_enable(WDTO_2S);');
}

void loop() {
  cpp('wdt_reset();');
}
```

- `cpp('…')` is a **statement of its own** (E019 anywhere else, e.g. inside an expression or as a value). Its
  argument is a single string literal, possibly raw or adjacent literals, without interpolation (E019). The text is
  emitted verbatim on its own line(s) after a `#line` directive, at the current indentation.
- Unodar does not parse or check the C++. It does reject text that allocates on the heap, by word: `new`, `delete`,
  `malloc`, `calloc`, `realloc`, `free`, `String` (E020). Comments and string literals inside the C++ are not
  exempt.
- `@CppInclude('File.h')` is allowed only on the `library;` directive (E017 elsewhere), may repeat, and takes a
  plain header path. Each header is included once, as `#include <File.h>`, after `Arduino.h` and the binding
  headers, in source order.

## Widgets: `runDevice`

A **widget program** describes the device as a tree instead of writing `setup()` and `loop()`. The compiler reads
the tree **statically** (it never runs `main()`) and generates flat C++: one statically allocated object per widget,
a plain function per callback, and a `setup()`/`loop()` that drive them. No heap, no virtual calls, no function
pointers.

```dart
import 'package:unodar/unodar.dart';

final led = Led(pin: 13);
final button = Button(
    pin: 2,
    onPressed: () {
      led.toggle();
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          button,
          Every(Duration(milliseconds: 500), () {
            Serial.println('tick');
          }),
        ],
      ),
    );
```

```cpp
#include <Arduino.h>
#include "unodar_widgets.h"

void unodar_button_onPressed();
void unodar_every_0_callback();

unodar::Led led(13);
unodar::Button button(2);
unodar::Every unodar_every_0(500);

void unodar_button_onPressed() {
  led.toggle();
}

void unodar_every_0_callback() {
  Serial.println(F("tick"));
}

void setup() {
  Serial.begin(9600);
  led.begin();
  button.begin();
  unodar_every_0.begin();
}

void loop() {
  if (button.pressed()) {
    unodar_button_onPressed();
  }
  if (unodar_every_0.due()) {
    unodar_every_0_callback();
  }
}
```

(`#line` directives omitted here.)

### The program

- `main()` is exactly `void main() => runDevice(Device(…));` or `void main() { runDevice(Device(…)); }`: one call,
  nothing else (E008). With `main()`, the file has no `setup()` or `loop()` (E021); a file with `setup()`/`loop()`
  cannot use widgets or `runDevice` (E021).
- `Device(board: Uno(), children: […], {serialBaud = 9600})`. `board` is `Uno()` (the only board in this version);
  `children` is a list literal of widgets, without spreads or collection `if`/`for` (E021).
- The generated `setup()` calls `Serial.begin(serialBaud)` first, but only if the program uses `Serial`, so
  callbacks can print straight away. `Serial.begin` itself is rejected in a widget program (E021): set
  `serialBaud:` instead, a compile-time constant (E021; negative values are E004). The default, 9600, is read from
  the Dart declaration of `Device`.
- Other top-level declarations work as in any sketch: variables, functions (callable from callbacks), bindings and
  bound objects, `@CppInclude`.

### Widgets

| Widget | Arguments | Behaviour |
|---|---|---|
| `Led(pin: p)`, `Led(pin: p, on: flag)` | `pin` 0–19 (D0–D13, A0–A5); `on` a `Signal<bool>` or `Computed<bool>` | Output, starts **off** (LOW). Methods `on()`, `off()`, `toggle()`, `set(b)`. With `on:`, the LED follows the signal instead and has no methods (see [Signals](#signals)). |
| `Button(pin: p, onPressed: () { … })` | `pin` 0–19 | Input with the internal pull-up (`INPUT_PULLUP`): wire the button between the pin and GND, no resistor. `onPressed` runs **once per press**, when the reading changes from HIGH to LOW and stays there for **50 ms** (debounced). Releasing runs nothing. A button already held at power-up does not count as a press. |
| `Every(Duration(…), () { … })` | interval 1 ms to 2147483647 ms | Runs the callback **after one interval**, then every interval, measured from `setup()`. |
| `Watch(signal, (v) { … })` | a top-level `Signal` or `Computed` | Runs the callback with the value when the signal changes, and once at the end of `setup()` (see [Signals](#signals)). |

- A widget is either a top-level `final` (`final led = Led(pin: 13);`), which gives a handle callbacks can use, or
  written directly in `children` (no handle). Anywhere else, e.g. a local variable, inside a callback, or in a
  plain sketch, it is rejected (E022, E021).
- Every argument is a compile-time constant: `pin` like any constant (`13`, `A0`, a `const`); the interval a
  `Duration(…)` with constant `days:`/`hours:`/`minutes:`/`seconds:`/`milliseconds:`/`microseconds:` arguments that
  add up to a whole number of milliseconds (E022). Pins outside 0–19 are E004.
- Each pin is used by at most one widget, and every top-level widget is listed in `children` exactly once (E022).
  A top-level widget's callback may only use widgets declared **above** it (E022), the same order rule as
  top-level initializers.
- `children` order is the order of `setup()` initialization and of polling in `loop()`.
- A widget handle can only be used to call its methods (`led.toggle()`) and to be listed in `children` (E022), as
  with bound objects. `Button`, `Every` and `Watch` have no methods yet.

### Callbacks

`onPressed`, `Every`'s and `Watch`'s callbacks are closures: `() { … }` or `() => call(…)`, and `(v) { … }` for
`Watch`. Each becomes a generated plain function (`unodar_button_onPressed`, `unodar_every_0_callback`,
`unodar_watch_0_callback`).

- No parameters (`Watch`: exactly one, the value), not `async`, no return value; a function reference
  (`onPressed: toggle`) is not accepted, write `() { toggle(); }` (E012).
- The body follows the same rules as a function body: statements, expressions, calls, its own local variables. It
  may use top-level variables and constants, call your top-level functions and the unodar API, use `Serial` (but
  not `Serial.begin`), widget handles, bound objects, and `cpp()`.
- No closures inside a callback (E012). Closures anywhere else remain rejected (E012).
- No `delay()`, directly or through a function the callback calls (E023): while a callback waits, no button is
  read and no timer runs.

### Timing

The generated `loop()` polls every widget, in `children` order, on every pass; callbacks run inside `loop()`, one
after the other, never at the same time. A program with signals ends every pass with their delivery (see
[Signals](#signals)).

- `Every` is **drift-free**: each tick is scheduled exactly one interval after the previous **scheduled** tick
  (`last += interval`), not after the moment the callback ran. It is **wrap-safe**: it compares `now - last >=
  interval` in unsigned 32-bit arithmetic, which stays correct when `millis()` wraps after about 49.7 days.
- If callbacks run for longer than an interval, the missed ticks of an `Every` run on the following `loop()` passes,
  one per pass, until it has caught up.
- `Button` debouncing uses the same wrap-safe comparison.

## Signals

**Status: specified, being implemented on the `phase-5` branch (`docs/PLAN.md` steps 3–11).** `package:unodar`
declares `Signal`, `ReadonlySignal`, `Watch`, `Led(on:)` and `Led.set` (step 3), so autocomplete and `dart analyze`
know them. Compiled so far: signals as state (declaring, reading, writing; step 5). Until each remaining construct's
compiler step lands, the compiler rejects it with diagnostics (for `led.set(…)`: E003, "not supported in this
version"). `Computed` is declared in step 10.

A **signal** holds a value and tells the widgets that watch it when the value changes. Signals are statically
allocated globals: no heap, no listener lists, no function pointers. Everything about who watches what is known at
compile time, so the compiler generates one flat function that delivers changes.

```dart
import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final isOdd = Computed(() => count.value % 2 == 1);
final led = Led(pin: 13, on: isOdd);
final plus = Button(
    pin: 2,
    onPressed: () {
      count.value++;
    });
final clear = Button(
    pin: 3,
    onPressed: () {
      count.value = 0;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          plus,
          clear,
          Watch(count, (v) {
            Serial.println(v);
          }),
        ],
      ),
    );
```

```cpp
#include <Arduino.h>
#include "unodar_widgets.h"

constexpr int32_t unodar_mod(int32_t a, int32_t b) { return a % b < 0 ? (b < 0 ? a % b - b : a % b + b) : a % b; }

bool unodar_isOdd_compute();
void unodar_plus_onPressed();
void unodar_clear_onPressed();
void unodar_watch_0_callback(int32_t v);
void unodar_deliver();

unodar::Signal<int32_t> count(0);
unodar::Signal<bool> isOdd(false);
unodar::Led led(13);
unodar::Button plus(2);
unodar::Button clear(3);

bool unodar_isOdd_compute() {
  return unodar_mod(count.value(), 2) == 1;
}

void unodar_plus_onPressed() {
  count.set(count.value() + 1);
}

void unodar_clear_onPressed() {
  count.set(0);
}

void unodar_watch_0_callback(int32_t v) {
  Serial.println(v);
}

void unodar_deliver() {
  const bool unodar_count_changed = count.take();
  const int32_t unodar_count_value = count.value();
  if (unodar_count_changed) {
    isOdd.set(unodar_isOdd_compute());
  }
  const bool unodar_isOdd_changed = isOdd.take();
  const bool unodar_isOdd_value = isOdd.value();
  if (unodar_count_changed) {
    unodar_watch_0_callback(unodar_count_value);
  }
  if (unodar_isOdd_changed) {
    led.set(unodar_isOdd_value);
  }
}

void setup() {
  Serial.begin(9600);
  led.begin();
  plus.begin();
  clear.begin();
  unodar_deliver();
}

void loop() {
  if (plus.pressed()) {
    unodar_plus_onPressed();
  }
  if (clear.pressed()) {
    unodar_clear_onPressed();
  }
  unodar_deliver();
}
```

(`#line` directives omitted. This listing becomes a tested example with `examples/counter`, plan step 13.)

At boot this prints `0` and leaves the LED off. Each press on pin 2 prints the next count and switches the LED
on for odd counts; a press on pin 3 prints `0`, unless the count is already 0, which prints nothing.

### Declaring, reading, writing

| Dart | Rule | C++ |
|---|---|---|
| `final count = Signal<int>(0);`, `final on = Signal(true);` | A top-level `final` in a widget program. `T` is `int`, `double`, `bool`, `Uint8`, `Uint16` or `Int16` (E009), explicit or inferred from the initial value, which is a compile-time constant (E015). | `unodar::Signal<int32_t> count(0);` |
| `count.value` | Read, anywhere an expression of type `T` is allowed. | `count.value()` |
| `count.value = e;` and `+=`, `-=`, `++`, `--` | Write. Statements only, like assignments to variables. A sized signal is written back with its constructor: `level.value = Uint8(level.value + 1);`. | `count.set(e);`, `count.set(count.value() + 1);` |

- A signal is used only through `.value` (E024): it cannot be stored in another variable, compared, passed,
  printed, or returned, and no local, parameter, or return value has a signal type. It is not a widget and is not
  listed in `children`.
- Callbacks and the functions they call may read and write any signal, wherever it is declared.
- A `.value` read counts as a read of mutable top-level state for the evaluation-order rule (E013): write
  `final n = next();` before `count.value + n`.
- Signals, `Watch` and `Computed` only exist in widget programs; in a `setup()`/`loop()` sketch they are E021.

### Watching: `Watch`

`Watch(signal, (v) { … })` is a widget: a top-level `final` or written in `children`, listed exactly once (E022).
Its first argument is the name of a top-level `Signal` or `Computed` declared above it (E024, E015); the callback
takes exactly one parameter, the value, of the signal's type, and follows every rule of widget callbacks, including
no `delay()` (E023). A signal may have any number of Watches.

### When changes are delivered

A `loop()` pass has two phases:

1. **Inputs and timers.** Every `Button` and `Every` is polled in `children` order and runs its callback, as
   without signals. A write only stores the value and marks the signal changed; it never runs other code.
2. **Delivery.** First, for every signal in declaration order, its changed mark is taken (and cleared) and its
   value is read; a `Computed` whose dependencies changed is re-evaluated at its place in that order. Then, for
   every signal that changed, in declaration order, its observers run in `children` order: each `Watch` callback
   with the value read in the first half, and each `Led(on: …)` is switched to it.

So:

- A press or tick is seen by the Watches in the **same** pass.
- A write made during delivery (by a Watch callback) is delivered in the **next** pass, wherever the signal is
  declared.
- Each Watch runs at most once per pass, and all observers of one signal see the same value in that pass.
- Several writes in one pass are delivered once, with the last value. A sequence that ends where it started
  (0 → 1 → 0) is still delivered, with `0`.
- No callback ever runs inside another: delivery is one flat generated function, `unodar_deliver()`.
- **The first value is delivered once**, at the end of `setup()`, after every widget's `begin()`: every Watch
  runs once with its signal's initial value and every bound Led takes it. Writes made there arrive in the first
  `loop()` pass.

A Watch callback can still read another signal's `.value` directly; it then sees that signal's current value,
including writes made earlier in the same delivery.

### Change detection

A write of a value equal to the current one (`==`) does nothing: the signal is not marked and nothing is
delivered, as with Flutter's `ValueNotifier`. Doubles compare as in Dart: writing `double.nan` is always a change
(`NaN != NaN`), and writing `-0.0` onto `0.0` is not (the value stays `0.0`).

### No cycles

A Watch callback may not write the signal it watches, directly or through functions it calls, and Watches may not
write each other's signals in a circle (`Watch(a)` writes `b`, `Watch(b)` writes `a`): E025, with the path. Such a
program would deliver on every pass for ever. Write a signal where the change starts (in a Button or Every
callback), or derive the value with a `Computed`. Because the watch graph has no cycles, the program is quiet again
after a bounded number of passes following any input.

### Derived values: `Computed`

```dart
final isOdd = Computed(() => count.value % 2 == 1);
final percent = Computed(() => level.value * 100 ~/ 1023);
```

- The closure is a single `=>` expression of a supported type. It may use `.value` of signals and Computeds
  declared **above** it, literals, constants (`const` variables, unodar constants), `Uint8(…)`/`Uint16(…)`/
  `Int16(…)`, and the operators of the subset. Anything else is E026: a block body, any call (including
  `analogRead`), an assignment, or a mutable top-level variable (the Computed would not see it change).
- Since a Computed only reads what is declared above it, there can be no cycles.
- **Reading** `isOdd.value` evaluates the expression (`unodar_isOdd_compute()`), so it always equals the expression
  over the current signal values, even in the middle of a delivery. A Computed cannot be written (no setter, E007).
- **Watching** it (`Watch`, `Led(on: …)`) works as for a signal. In delivery, a Computed with a changed dependency is
  re-evaluated and compared with the value it last delivered; it is delivered only if that differs, so `isOdd`
  stays silent when the count goes from 0 to 2. Computeds are settled before any observer runs.
- Its C++ object stores the last delivered value, starting at `T`'s zero (`0`, `0.0`, `false`); the delivery at
  the end of `setup()` evaluates it first.

### LEDs that follow a signal

`Led(pin: 13, on: flag)`, with `flag` a `Signal<bool>` or `Computed<bool>` declared above it (E015), is switched to
the signal's value at the end of `setup()` and whenever it changes. The signal is the only thing that drives it:
calling `on()`, `off()`, `toggle()` or `set()` on a bound Led is E022. An unbound Led can be switched to a `bool`
with `led.set(b)`.

### Cost

Sizes on the Uno (1-byte alignment, so no padding), fixed at build time:

| Object | RAM |
|---|---|
| `Signal<int>`, `Signal<double>` | 5 B (value and a changed mark) |
| `Signal<Uint16>`, `Signal<Int16>` | 3 B |
| `Signal<bool>`, `Signal<Uint8>` | 2 B |
| `Computed<T>` | as `Signal<T>` |
| `Watch`, `Led(on: …)` | 0 B (generated code only; a Led keeps its own 2 B) |

The values and marks taken during delivery are local variables. Delivery code is generated only for signals that
are watched or read by a Computed; a signal nobody observes is plain state with its 1-byte mark.

## Translation and layout

The generated file contains, in order: the `// Generated by unodar…` header; `#include <Arduino.h>`; the
`@CppHeader` of each binding the program uses, in the order of first use; the `@CppInclude` headers in source order;
any helpers the program uses (`unodar_mod`); a prototype for every user function except `setup`/`loop`; the
top-level variables and bound objects in source order; then the functions in source order. A `#line` directive
precedes every variable, function, and statement. Output is deterministic: the same input gives byte-identical
output on any machine.

A widget program also includes `"unodar_widgets.h"` after the binding and `@CppInclude` headers, declares its
widgets with the other top-level variables in source order (widgets written inside `children` after them, in list
order), emits each callback as a function, and ends with the generated `setup()` and `loop()` (their `#line` points
at `main()`). `unodar build` writes a copy of the fixed, hand-written runtime header `runtime/unodar_widgets.h` into
the sketch folder next to the `.ino`, and only for programs that use widgets.

Signals and Computeds are declared with the other top-level variables, in source order. Each Computed's function
(`unodar_<name>_compute`) sits at its declaration among the functions, each Watch callback with the other callbacks,
and `unodar_deliver()` right before the generated `setup()`. Its locals are named `unodar_<signal>_changed` and
`unodar_<signal>_value`, so they cannot shadow a user name (the `unodar_` prefix is reserved, E014).

## Building

Unodar sketches must be built with `-fwrapv`, which makes signed `int32_t` overflow wrap instead of being
undefined behaviour. The AVR core links with LTO, so the flag is needed when compiling and when linking:

```sh
arduino-cli compile --fqbn arduino:avr:uno \
  --build-property compiler.c.extra_flags=-fwrapv \
  --build-property compiler.cpp.extra_flags=-fwrapv \
  --build-property compiler.c.elf.extra_flags=-fwrapv \
  out/main
```

For a widget program, `out/main` holds `main.ino` and `unodar_widgets.h`; arduino-cli compiles the folder as is.
`tool/check_arduino.sh` and the test suite pass these properties; the `unodar` CLI will pass them itself from
Phase 7 (`unodar flash`/`run`). Building without them still compiles, but overflow (including `millis()` wrap
handling) is then undefined behaviour.

## Known deviations from Dart

These are the only places where generated C++ can behave differently from the same Dart program. They are runtime
conditions that cannot be detected at compile time; constant cases are rejected (E010, E004). The wraparound and
`millis()` rows are checked at runtime in a simulated Uno (avr8js) by `runtime_fidelity_test`, with a negative
control built without `-fwrapv`.

| Situation | Dart | Generated C++ |
|---|---|---|
| `int` overflow at runtime (a result outside -2147483648…2147483647, e.g. `a * b`, `a + b`, `-a` for large values) | Exact 64-bit result | **Wraps** (two's complement, modulo 2^32): `2147483647 + 1` is `-2147483648`. This is defined behaviour because unodar sketches are built with `-fwrapv` ([Building](#building)); without that flag it would be C++ undefined behaviour. Keep values in range where the exact result matters. |
| `x ~/ -1` at runtime when `x` is -2147483648 | 2147483648 (Dart's `int` is 64-bit) | **Undefined behaviour**: the quotient does not fit `int32_t`. On AVR it typically gives -2147483648. |
| `x % -1` at runtime when `x` is -2147483648 | 0 | **Undefined behaviour**: C++'s `%`, which `unodar_mod` starts from, overflows for this pair. Every other pair, including the divisor -2147483648, is exact. |
| Integer `~/` or `%` by a variable that is zero | Throws `IntegerDivisionByZeroException` | **Undefined**; on AVR the program continues with a meaningless result. No check is inserted. |
| `double` precision and range | 64-bit (≈15–17 digits, max ≈1.8e308) | 32-bit `float` (≈6–7 digits, max ≈3.4e38). An `int` mixed with a `double`, or divided with `/`, converts to `float` and keeps only 24 bits of precision (exact up to 16777216). |
| A non-constant value passed to an Arduino function or a binding parameter outside its C++ parameter type or its `@CppRange` | (external) | Converted to the C++ parameter type by C++ rules, e.g. `delay(-1)` waits about 49 days, a pin of 300 becomes 44; a value outside a `@CppRange` is passed unchanged and the library misbehaves (Servo wraps its `int8_t` offset). |
| `millis()` after about 24.8 days, `micros()` after about 35.8 minutes of uptime | (external) | The value passes 2147483647 and continues at -2147483648, wrapping like an `int32_t` (Arduino's `unsigned long` counter, converted). **Elapsed time stays correct**: `now - last` wraps too (`-fwrapv`), so `if (now - last >= interval)` works across the wrap for any interval below 2147483648. Comparing two readings directly (`now > last`) does not. |
| `Serial.print` of a `double` | (external; Dart's `toString()` would print `1.5`) | Arduino's fixed-point format: `digits` decimals (default 2), so `1.50`; `nan`, `inf`, and `ovf` (above about 4.3e9) for special values. |
| Bound objects | (external) | Constructed before `setup()` runs (C++ static initialization), not lazily on first use like a Dart top-level `final`. |
| Widget callbacks and timers | (no direct Dart equivalent; a Dart event loop would queue callbacks) | Callbacks run inside `loop()`, one after another, in `children` order; a slow callback delays the others. An `Every` that falls behind runs its missed ticks on the next passes, one per pass. |
| Signal delivery | (no direct Dart equivalent; a `ValueNotifier` calls its listeners synchronously on every change) | Changes are delivered once per `loop()` pass, after the inputs and timers: several writes in one pass are delivered once, with the last value, and a write made during delivery arrives one pass later ([When changes are delivered](#when-changes-are-delivered)). |

## Diagnostics summary

| Construct | Code |
|---|---|
| Missing `setup()` or `loop()` | E001 |
| Unsupported statement, operator, or expression form; a string literal outside a Serial argument; string interpolation | E002 |
| Call to a function or method that is neither declared in this file nor part of the unodar API or a binding (incl. `x.abs()`) | E003 |
| Constant argument out of range for an Arduino or binding parameter; `digits:` with a non-`double` value | E004 |
| Classes without `@CppClass`, enums, typedefs, extensions, getters/setters, `late` variables, `external` variables of a non-binding type, other imports, `export`/`part` | E005 |
| `setup`/`loop` not exactly `void name() { … }` | E006 |
| Any Dart analysis error | E007 |
| `main()` other than a single `runDevice(Device(…))` call | E008 |
| Unsupported or nullable type, incl. `String` variables, unsupported Serial arguments, and signal type arguments (`Signal<String>`); comparing a bool with a number | E009 |
| Constant out of range, constant overflow, constant division by zero | E010 |
| Optional/named/default parameters, generics, `async`, untyped parameters in a user function | E011 |
| Closures other than widget callbacks, callbacks with parameters, closures inside callbacks, function references, local functions | E012 |
| Code whose meaning depends on evaluation order, incl. a call next to a `.value` read | E013 |
| Name that collides with C++ or Arduino | E014 |
| Top-level initializer (or bound-object constructor argument, or signal initial value) that is not a compile-time constant; a signal argument of a widget declared below it | E015 |
| A function that calls itself, directly or through other functions | E016 |
| Invalid binding class or interop annotation | E017 |
| A bound object used other than as a top-level `final` whose methods are called | E018 |
| `cpp()` used other than as a statement with one string literal | E019 |
| Heap allocation in `cpp()` text | E020 |
| Widget program shape: `main()` with `setup()`/`loop()`, widgets or signals in a `setup()`/`loop()` sketch, `Device` arguments, `Serial.begin` | E021 |
| Widget rules: placement, constant arguments, duplicate pins, widgets (incl. `Watch`) missing from `children` or listed twice, use before declaration, handle misuse, methods on a bound Led | E022 |
| `delay()` in a widget callback (incl. `Watch`), directly or through a called function | E023 |
| Signal misuse: not a top-level `final`, used other than through `.value`, signal-typed locals/parameters/returns, a Watch source that is not a top-level signal | E024 |
| A Watch that writes the signal it watches, or Watches that write each other's signals in a cycle | E025 |
| `Computed` not a single expression over signals/Computeds declared above and constants | E026 |
| Your own classes | not yet available |
