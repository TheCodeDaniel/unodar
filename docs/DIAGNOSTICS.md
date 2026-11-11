# Diagnostics reference

Every diagnostic has a stable code, a severity, a `file:line:col` location, a message, and a suggestion:

```text
<file>:<line>:<col>: error[<code>]: <message>
  = help: <suggestion>
```

The file is the source's base name. Diagnostics are printed in source order, followed by a count line (`2 errors.`).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success: the sketch was written. |
| 1 | Diagnostics: fix your Dart source. |
| 2 | Tooling error: bad command-line usage, unreadable input, unwritable output, or an internal compiler error. |

## E001: Missing required `setup()` or `loop()`

Both entry points are required. Reported at 1:1, once per missing function.

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}
```

```text
input.dart:1:1: error[E001]: missing required function 'loop()'. Every unodar sketch needs both setup() and loop().
  = help: Add `void loop() { }` at the top level of this file.
```

(Golden test: `test/golden/e001_missing_loop`.)

## E002: Unsupported statement or expression kind

A statement, operator, or expression form that is outside the subset (see `docs/SUBSET.md`): `do`/`while`,
`switch`, `for`-`in`, labeled statements, `try`, `throw`, `assert`, empty statements; bitwise and shift operators,
`??`, `is`/`as`, `%` or `~/` on doubles, compound assignments other than `+=`/`-=`; assignments, `++`, or `--`
used inside a larger expression; property access such as `x.isEven`; strings, `null`, collection literals,
cascades. The suggestion is specific to the construct.

```dart
import 'package:unodar/unodar.dart';

int count = 0;

void setup() {}

void loop() {
  do {
    count *= 2;
  } while (count < 100);
  delay(count++);
}
```

```text
input.dart:8:3: error[E002]: a do-while loop is not supported in this version.
  = help: Use a `while` loop instead.
input.dart:9:5: error[E002]: the `*=` operator is not supported in this version.
  = help: Write the assignment out in full, e.g. `x = x * y;`. Only `=`, `+=`, and `-=` are supported.
input.dart:11:9: error[E002]: `++` inside an expression is not supported in this version.
  = help: Use `++` and `--` only as statements of their own, e.g. `count++;` on its own line.
```

(Golden tests: `test/golden/e002_do_while`, `e002_bitwise_operator`, `e002_assignment_in_expression`, …)

## E003: Call to a function that is not part of the supported unodar API

A call must resolve to a function declared at the top level of this file, or to one of the unodar API functions
`pinMode`, `digitalWrite`, `delay` declared in `package:unodar`. This includes undefined functions (the analyzer
would call this an "undefined name"; unodar reports E003 instead when the call is a statement of its own) and
method calls on a value or class (`x.abs()`, `Serial.println(…)`; when `Serial` itself is undefined the analyzer
reports E007).

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(8, OUTPUT);
}

void loop() {
  tone(8, 440);
}
```

```text
input.dart:8:3: error[E003]: unknown function 'tone'. Only functions declared in this file and the unodar API functions pinMode, digitalWrite, and delay can be called in this version.
  = help: Declare the function in this file, or remove this call. More Arduino functions arrive in a later phase; see docs/SUBSET.md.
```

(Golden tests: `test/golden/e003_unknown_function`, `e003_method_call`.)

## E004: Unsupported argument

An argument the unodar API function cannot accept:

- a **constant** argument outside the range of the Arduino C++ parameter type (`uint8_t` pin/mode/value:
  0 to 255; `unsigned long` milliseconds: not negative). Non-constant values are converted at runtime instead
  (see "Known deviations from Dart" in `docs/SUBSET.md`);
- a named argument. No API function has named parameters before Phase 3, so the analyzer already reports such a
  call as E007; E004 is the compiler's own guard behind it.

Arguments of a call that already got E003 are not checked.

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(-13, HIGH);
  delay(250 - 500);
}
```

```text
input.dart:8:16: error[E004]: argument -13 is out of range for parameter 'pin' of digitalWrite, which is a uint8_t (0 to 255).
  = help: Pass a value from 0 to 255.
input.dart:9:9: error[E004]: argument -250 is out of range for parameter 'ms' of delay, which is an unsigned long (0 to 4294967295).
  = help: Pass a value from 0 to 4294967295.
```

(Golden test: `test/golden/e004_argument_out_of_range`.)

## E005: Unsupported top-level declaration

Top-level functions and variables are supported; classes, enums, mixins, extensions, extension types, typedefs,
and top-level getters/setters are not, nor are `late` or `external` variables. Also used for directives: any import
other than an unprefixed `package:unodar/unodar.dart`, and `export`/`part`.

```dart
import 'package:unodar/unodar.dart';

class Blinker {}

late int ledPin;

void setup() {}

void loop() {}
```

```text
input.dart:3:1: error[E005]: a class is not supported in this version. Only top-level functions and variables may be declared.
  = help: Remove this declaration; see docs/SUBSET.md for what may be declared at the top level.
input.dart:5:1: error[E005]: a late variable ('ledPin') is not supported in this version. Only top-level functions and variables may be declared.
  = help: Remove `late` and give the variable a constant initializer.
```

(Golden tests: `test/golden/e005_class`, `e005_import`, `e005_late_variable`.)

## E006: Invalid `setup`/`loop` signature

Must be exactly `void name() { ... }`. All problems with one function are listed in a single diagnostic, at the function name.

```dart
import 'package:unodar/unodar.dart';

void setup(int pin) {
  pinMode(13, OUTPUT);
}

loop() {}
```

```text
input.dart:3:6: error[E006]: invalid signature for 'setup': it takes parameters.
  = help: Declare it exactly as `void setup() { ... }`: return type void, no parameters, a block body.
input.dart:7:1: error[E006]: invalid signature for 'loop': it has no return type.
  = help: Declare it exactly as `void loop() { ... }`: return type void, no parameters, a block body.
```

(Golden test: `test/golden/e006_bad_signature`.)

## E007: Dart analysis error in the source file

Any analyzer *error* (warnings and hints are ignored): type errors, syntax errors, unresolved imports. When any E007 is present, compilation stops before the subset checks, because a broken AST produces misleading follow-on diagnostics.

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, 'output');
}

void loop() {}
```

```text
input.dart:4:15: error[E007]: Dart analysis error: The argument type 'String' can't be assigned to the parameter type 'int'.
  = help: Fix the Dart error first; `dart analyze` on this file shows the same problem.
```

(Golden test: `test/golden/e007_type_error`.)

## E008: `main()` is reserved

`main()` is reserved for the widget API (`runDevice`, Phase 4). It is not compiled.

```dart
import 'package:unodar/unodar.dart';

void main() {}

void setup() {}

void loop() {}
```

```text
input.dart:3:6: error[E008]: 'main()' is reserved for the widget API (runDevice), which arrives in a later phase.
  = help: Remove main() and put your code in `void setup()` and `void loop()` instead.
```

(Golden test: `test/golden/e008_main`.)


## E009: Unsupported type

Only `int`, `double`, `bool`, `Uint8`, `Uint16`, `Int16` (and `void` as a return type) are supported. Reported for
declared types (variables, parameters, return types) and for the inferred static type of any expression, so
`flag ? 1 : 2.5` (type `num`) is rejected. Nullable types get their own wording. Also used for `==`/`!=` between a
`bool` and a number: Dart says they are never equal, C++ says `true == 1`.

```dart
import 'package:unodar/unodar.dart';

int? lastPin;

void setup() {}

void loop() {
  final speed = true ? 1 : 2.5;
}
```

```text
input.dart:3:1: error[E009]: the nullable type 'int?' is not supported in this version.
  = help: Use the non-nullable type 'int' and give the variable a value.
input.dart:8:17: error[E009]: the type 'num' is not supported in this version. Only int, double, bool, Uint8, Uint16, and Int16 are supported.
  = help: Make both branches the same type, e.g. write `1.0` instead of `1`.
```

(Golden tests: `test/golden/e009_nullable_type`, `e009_unsupported_type`, `e009_bool_number_comparison`.)

## E010: Constant out of range

A compile-time constant that cannot be represented exactly in the C++ type: an integer literal above 2147483647,
any intermediate result of a constant `int` expression outside -2147483648…2147483647, a double literal above the
`float` maximum, or a constant division by zero (`~/`, `%`, or `/` on ints). Unodar `int` is `int32_t`, not Dart's
64-bit `int`.

```dart
import 'package:unodar/unodar.dart';

void setup() {}

void loop() {
  delay(60 * 60 * 1000 * 1000);
  delay(1000 ~/ 0);
}
```

```text
input.dart:6:9: error[E010]: this constant expression computes 3600000000, which is outside the 32-bit int range (-2147483648 to 2147483647).
  = help: unodar ints are 32-bit (int32_t). Use smaller values; see "Known deviations from Dart" in docs/SUBSET.md.
input.dart:7:9: error[E010]: this constant expression divides by zero.
  = help: Use a divisor that is not zero.
```

(Golden tests: `test/golden/e010_constant_overflow`, `e010_literal_out_of_range`, `e010_division_by_zero`.)

## E011: Unsupported function signature

User-defined functions take only required, positional parameters with an explicit supported type, have no type
parameters, and are not `async`, generators, or `external`. All problems with one function are listed in one
diagnostic, at the function name. (`setup` and `loop` have their own rule, E006.)

```dart
import 'package:unodar/unodar.dart';

void blink(int pin, [int times = 1]) {}

T first<T>(T a) => a;

void setup() {}

void loop() {}
```

```text
input.dart:3:6: error[E011]: unsupported signature for function 'blink': it has optional positional parameters and a default value.
  = help: Use only required positional parameters with a supported type, e.g. `int add(int a, int b) { ... }`.
input.dart:5:3: error[E011]: unsupported signature for function 'first': it has type parameters.
  = help: Use only required positional parameters with a supported type, e.g. `int add(int a, int b) { ... }`.
```

(Golden tests: `test/golden/e011_optional_parameter`, `e011_named_parameter`, `e011_generic_function`.)

## E012: Closure or function value

Functions can only be declared at the top level and called directly. Closures (`() => …`), function references
(using `pulse` without calling it), and local functions need captured state or function pointers, which arrive
(restricted) with the widget API.

```dart
import 'package:unodar/unodar.dart';

void pulse() {}

void setup() {
  final f = pulse;
}

void loop() {}
```

```text
input.dart:6:13: error[E012]: a function reference ('pulse') is not supported in this version. Functions can only be called directly.
  = help: Call the function instead, e.g. `pulse()`.
```

(Golden tests: `test/golden/e012_closure`, `e012_function_reference`, `e012_local_function`.)

## E013: Evaluation order differs in C++

Dart evaluates operands and arguments left to right; C++ leaves the order unspecified. Within one operator's
operands, one call's argument list, or the two sides of `+=`/`-=`, a call to a user function may not sit next to
another call or next to a read of a mutable top-level variable (the call might change it). `&&`, `||`, and `?:`
fix the order and are always fine.

```dart
import 'package:unodar/unodar.dart';

int count = 0;

int next() {
  count += 1;
  return count;
}

void setup() {}

void loop() {
  delay(count + next());
}
```

```text
input.dart:13:17: error[E013]: 'next()' may run before or after 'count' is read in the generated C++, but Dart always evaluates left to right.
  = help: Store the call's result in a local variable first, e.g. `final value = next();`.
```

(Golden tests: `test/golden/e013_call_and_global`, `e013_two_calls`, `e013_compound_assignment`.)

## E014: Reserved name

A user-declared name (top-level variable, function, parameter, or local) that would collide with C++ or the Arduino
core in the generated code: a C++ keyword, a unodar API name, an Arduino core or avr-libc function or macro, an
ALL-CAPS name, or a name reserved by C/C++ or unodar (`_t` suffix, `__`, `$`, `_` plus upper-case, `unodar_`
prefix). See the Names section of `docs/SUBSET.md`.

```dart
import 'package:unodar/unodar.dart';

const int LED_PIN = 13;

int min(int a, int b) => a < b ? a : b;

void setup() {
  int and = 1;
}

void loop() {}
```

```text
input.dart:3:11: error[E014]: 'LED_PIN' cannot be used as a name: all-caps names are reserved for C and Arduino macros.
  = help: Rename it, e.g. `ledPin`.
input.dart:5:5: error[E014]: 'min' cannot be used as a name: it is an Arduino core or avr-libc function or macro.
  = help: Rename it, e.g. `minValue`.
input.dart:8:7: error[E014]: 'and' cannot be used as a name: it is a C++ keyword.
  = help: Rename it, e.g. `andValue`.
```

(Golden tests: `test/golden/e014_all_caps`, `e014_arduino_name`, `e014_cpp_keyword`, `e014_api_name`,
`e014_reserved_pattern`.)

## E015: Top-level initializer is not a compile-time constant

Every top-level variable needs an initializer made only of literals, unodar constants, `const` variables declared
**above** it, `Uint8(…)`/`Uint16(…)`/`Int16(…)` of constants, and supported operators. C++ initializes globals before
`setup()` runs and needs declarations before use, while Dart initializes them lazily, so anything else could run
in a different order. Compute other values in `setup()`.

```dart
import 'package:unodar/unodar.dart';

int twice(int x) => x * 2;

int a = twice(2);
const int b = c + 1;
const int c = 1;

void setup() {}

void loop() {}
```

```text
input.dart:5:9: error[E015]: the initializer of top-level variable 'a' is not a compile-time constant.
  = help: Use only literals, unodar constants, and `const` variables declared above it; assign other values in setup().
input.dart:6:15: error[E015]: the initializer of top-level variable 'b' refers to 'c', which is declared later.
  = help: Move the declaration of 'c' above 'b'.
```

(Golden tests: `test/golden/e015_non_constant_initializer`, `e015_forward_reference`.)
