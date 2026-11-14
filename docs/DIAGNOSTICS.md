# Diagnostics reference

Every example below is compiled by `test/unit/docs_test.dart`, which fails if the compiler's output differs from
the text shown. Every diagnostic has a stable code, a severity, a `file:line:col` location, a message, and a suggestion:

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

Both entry points are required in a sketch without `main()`. A widget program (`void main() => runDevice(…)`)
has neither; see E008 and E021. Reported at 1:1, once per missing function.

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
used inside a larger expression; property access such as `x.isEven`; a string literal anywhere except as the argument of `Serial.print`/`println`,
string interpolation, a string containing a NUL character; `null`, collection literals, cascades. The suggestion is
specific to the construct. A rejected statement (such as a `do` loop) is reported
as a whole; the code inside it is checked once it has been rewritten.

```dart
import 'package:unodar/unodar.dart';

int count = 0;

void setup() {}

void loop() {
  do {
    count += 1;
  } while (count < 100);
  count *= 2;
  delay(count++);
}
```

```text
input.dart:8:3: error[E002]: a do-while loop is not supported in this version.
  = help: Use a `while` loop instead.
input.dart:11:3: error[E002]: the `*=` operator is not supported in this version.
  = help: Write the assignment out in full, e.g. `x = x * y;`. Only `=`, `+=`, and `-=` are supported.
input.dart:12:9: error[E002]: `++` inside an expression is not supported in this version.
  = help: Use `++` and `--` only as statements of their own, e.g. `count++;` on its own line.
```

(Golden tests: `test/golden/e002_do_while`, `e002_statements`, `e002_operators`, `e002_double_operators`,
`e002_expressions`, `e002_assignment_in_expression`, `e002_string_outside_serial`, `e002_string_interpolation`.)

## E003: Call to a function that is not part of the supported unodar API

A call must resolve to a function declared at the top level of this file, to a unodar API function declared in
`package:unodar` (see "Calling the unodar API" in `docs/SUBSET.md`), or to a method of `Serial`, of a bound object,
or of an external object. This includes undefined functions (the analyzer would call this an "undefined name";
unodar reports E003 instead when the call is a statement of its own) and method calls on numbers (`x.abs()`). A
method that the binding does not declare is a Dart error (E007). A widget method that `package:unodar` declares
but this compiler version does not support yet is E003 too ("the Led method 'set' is not supported in this
version"). The suggestion points to the escape hatch,
`cpp('…')`, for Arduino functions unodar does not wrap yet.

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
input.dart:8:3: error[E003]: unknown function 'tone': it is neither declared in this file nor part of the unodar API.
  = help: Declare the function in this file, or call the Arduino function through the escape hatch, e.g. `cpp('tone(8, 440);');`. See docs/SUBSET.md for the unodar API.
```

(Golden tests: `test/golden/e003_unknown_function`, `e003_method_call`, `e003_widget_method`.)

## E004: Unsupported argument

An argument the unodar API function cannot accept:

- a **constant** argument outside the range of the Arduino C++ parameter type (`uint8_t` pin/mode/value:
  0 to 255; `int` analog value: -32768 to 32767; `unsigned long` milliseconds and baud rate: not negative), or of
  a binding parameter's `@CppType`, or of its narrower `@CppRange` (Servo's `attach` `min:` 33 to 1059, `max:`
  1889 to 2915). A `@CppRange` violation is reported as "…, which accepts 33 to 1059 (`@CppRange`).". Non-constant
  values are converted at runtime instead (see "Known deviations from Dart" in `docs/SUBSET.md`);
- `digits:` given to `Serial.print`/`println` with a value that is not a `double` (for an `int`, Arduino's second
  argument would mean the number base);
- a widget pin outside 0 to 19, the Uno's pins (D0–D13, and A0–A5 as 14–19), reported as "pin 20 is out of range
  for Led: …";
- a named argument the function does not declare. The analyzer already reports such a call as E007; E004 is the
  compiler's own guard behind it.

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

(Golden tests: `test/golden/e004_argument_out_of_range`, `e004_more_ranges`, `e004_core_io_ranges`,
`e004_serial_digits`, `e004_binding_ranges`, `e004_wire_ranges`, `e004_servo_ranges`, `e004_servo_pulse_min`,
`e004_servo_pulse_max`, `e004_widget_pins`, `e004_serial_baud`.)

## E005: Unsupported top-level declaration

Top-level functions and variables are supported, and so are binding classes (annotated `@CppClass`, checked by
E017) and `external` objects of a binding type. Classes without `@CppClass`, enums, mixins, extensions, extension
types, typedefs, and top-level getters/setters are not, nor are `late` variables or `external` variables of any
other type. Also used for directives: any import other than an unprefixed `package:unodar/unodar.dart`, and
`export`/`part`.

```dart
import 'package:unodar/unodar.dart';

class Blinker {}

late int ledPin;

void setup() {}

void loop() {}
```

```text
input.dart:3:1: error[E005]: a class without @CppClass is not supported in this version. Only top-level functions, variables, and binding classes may be declared.
  = help: Remove this declaration, or annotate it with `@CppClass('CppName')` if it describes a C++ class; see docs/SUBSET.md.
input.dart:5:1: error[E005]: a late variable ('ledPin') is not supported in this version. Only top-level functions, variables, and binding classes may be declared.
  = help: Remove `late` and give the variable a constant initializer.
```

(Golden tests: `test/golden/e005_class`, `e005_import`, `e005_other_declarations`.)

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

## E008: Unsupported `main()`

`main()` is only for widget programs, and must be exactly one call, `void main() => runDevice(Device(…));` or
`void main() { runDevice(Device(…)); }`. The compiler reads that call statically and never compiles `main()`
itself, so anything else is rejected: other statements or calls, parameters, a return type other than `void`,
`async`, or a `runDevice` argument that is not a `Device(…)` constructor call. To write code that runs once and
then in a loop, use `setup()` and `loop()` instead.

```dart
import 'package:unodar/unodar.dart';

void main() {
  pinMode(13, OUTPUT);
}
```

```text
input.dart:3:6: error[E008]: unsupported main(): it may only contain a single `runDevice(Device(…))` call.
  = help: Describe the device with widgets, e.g. `void main() => runDevice(Device(board: Uno(), children: [Led(pin: 13)]));`, or write `setup()` and `loop()` instead.
```

A file whose `main()` is rejected is neither a widget program nor a plain sketch, so its `setup()`/`loop()` and its
widgets are not checked further until `main()` is fixed.

(Golden tests: `test/golden/e008_main`, `e008_main_shapes`.)


## E009: Unsupported type

Only `int`, `double`, `bool`, `Uint8`, `Uint16`, `Int16` (and `void` as a return type) are supported. Reported for
declared types (variables, parameters, return types) and for the inferred static type of any expression, so
`flag ? 1 : 2.5` (type `num`) is rejected. `String` is rejected everywhere except a string literal passed to
`Serial.print`/`println`; any other type passed there is rejected too. Binding types outside a top-level `final`
are E018 instead. Signal type arguments follow the same list: `Signal<String>`, `Signal<num>`, `Signal<int?>` are
E009. Nullable types get their own wording. Also used for `==`/`!=` between a
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

(Golden tests: `test/golden/e009_nullable_type`, `e009_unsupported_type`, `e009_types`,
`e009_bool_number_comparison`, `e009_string_variable`.)

## E010: Constant out of range

A compile-time constant that cannot be represented exactly in the C++ type: an integer literal above 2147483647,
any intermediate result of a constant `int` expression outside -2147483648…2147483647, a double literal above the
`float` maximum, or a constant division by zero (`~/`, `%`, or `/`). `-2147483648 % -1` is also rejected: Dart gives 0,
but C++ computes it through the quotient 2147483648, which overflows. Unodar `int` is `int32_t`, not Dart's 64-bit
`int`.

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

(Golden tests: `test/golden/e010_constant_overflow`, `e010_literal_out_of_range`, `e010_division_by_zero`,
`e010_global_overflow`.)

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

(Golden tests: `test/golden/e011_optional_parameter`, `e011_signatures`.)

## E012: Closure or function value

Functions can only be declared at the top level and called directly. The one place a closure is allowed is a widget
callback (`Button(onPressed: () { … })`, `Every(…, () { … })`), where it becomes a generated plain function. It
takes no parameters, is not `async`, returns nothing, and contains no closures of its own; a function reference
(`onPressed: toggle`) is not accepted there either. Everywhere else, closures (`() => …`), function references (using
`pulse` without calling it), and local functions are rejected: they would need captured state or function
pointers.

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

A `Watch` callback takes exactly one parameter, the value (the analyzer checks its type, E007), and otherwise
follows the same rules. The closure of a `Computed` is the one other allowed closure; its body is checked by E026.

(Golden tests: `test/golden/e012_closure`, `e012_function_reference`, `e012_local_function`,
`e012_widget_callbacks`.)

## E013: Evaluation order differs in C++

Dart evaluates operands and arguments left to right; C++ leaves the order unspecified. Within one operator's
operands, one call's argument list, or the two sides of `+=`/`-=`, two calls of any kind may not sit next to each
other (your functions, Arduino functions such as `micros() - micros()`, methods such as `Wire.read() + Wire.read()`),
and a call to a user function may not sit next to a read of a mutable top-level variable or of a signal's `.value`
(the call might change it). A call nested inside another call's argument is fine. `&&`, `||`, and `?:` fix the order and are always fine.

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

(Golden tests: `test/golden/e013_call_and_global`, `e013_two_calls`, `e013_arguments`, `e013_compound_assignment`,
`e013_api_calls`, `e013_method_calls`.)

## E014: Reserved name

A user-declared name (top-level variable, function, parameter, or local) that would collide with C++ or the Arduino
core in the generated code: a C++ keyword, a unodar API name, an Arduino core or avr-libc function or macro, an
ALL-CAPS name, or a name reserved by C/C++ or unodar (`_t` suffix, `__`, `$`, `_` plus upper-case, `unodar_`
prefix). See the Names section of `docs/SUBSET.md`. Also a top-level widget whose generated callback would get the
same C++ name as the callback of a widget written in `children`: a `Button` named `button_0` and the first inline
`Button` would both have `unodar_button_0_onPressed` (only reported when that inline widget exists).

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
input.dart:5:5: error[E014]: 'min' cannot be used as a name: it is already defined by the Arduino core or avr-libc.
  = help: Rename it, e.g. `minValue`.
input.dart:8:7: error[E014]: 'and' cannot be used as a name: it is a C++ keyword.
  = help: Rename it, e.g. `andValue`.
```

(Golden tests: `test/golden/e014_all_caps`, `e014_arduino_name`, `e014_cpp_keyword`, `e014_api_name`,
`e014_reserved_pattern`, `e014_generated_name`.)

## E015: Top-level initializer is not a compile-time constant

Every top-level variable needs an initializer made only of literals, unodar constants, `const` variables declared
**above** it, `Uint8(…)`/`Uint16(…)`/`Int16(…)` of constants, and supported operators. The constructor arguments of
a bound object (`final link = SoftSerial(10, 11);`) and the initial value of a signal (`Signal(analogRead(A0))` is
rejected) follow the same rule; widget arguments are checked by E022 instead, except for declaration order (a widget's arguments are emitted in its C++ declaration). C++ initializes globals before
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

A widget's signal argument (the source of a `Watch`, the `on:` of a `Led`) must be declared above the widget, for
the same reason.

(Golden tests: `test/golden/e015_non_constant_initializer`, `e015_forward_reference`, `e015_constructor_argument`,
`e015_widget_forward_reference`.)

## E016: Recursive function

A function that calls itself, directly or through other user functions. The compiler checks the call graph of
all functions in the file (including `setup` and `loop`) for cycles and reports each cycle once, at the first
function of the cycle in source order, with the path. Recursion is rejected because the Uno's 2 KB stack has no
overflow check: Dart would throw `StackOverflowError`, the board would silently corrupt memory.

```dart
import 'package:unodar/unodar.dart';

int factorial(int n) => n <= 1 ? 1 : n * factorial(n - 1);

void ping(int n) {
  if (n > 0) pong(n - 1);
}

void pong(int n) {
  if (n > 0) ping(n - 1);
}

void setup() {}

void loop() {}
```

```text
input.dart:3:5: error[E016]: recursion is not supported: 'factorial' calls itself through factorial → factorial.
  = help: Rewrite it with a loop. The Uno's 2 KB stack has no overflow check, so recursion is rejected.
input.dart:5:6: error[E016]: recursion is not supported: 'ping' calls itself through ping → pong → ping.
  = help: Rewrite it with a loop. The Uno's 2 KB stack has no overflow check, so recursion is rejected.
```

(Golden tests: `test/golden/e016_direct_recursion`, `e016_mutual_recursion`.)

## E017: Invalid binding class or interop annotation

A binding class (`@CppClass`) that breaks the rules in "Binding C++ classes" in `docs/SUBSET.md`: a field, getter,
setter, operator, static member, named constructor, or member with a body; `extends`/`implements`/`with` or type
parameters; an optional positional parameter, a named parameter without a constant default (and not `required`),
or an unsupported parameter or return type. Also an interop annotation in the wrong place or with a bad argument:
`@CppInclude` anywhere but the `library;` directive, `@CppName`/`@CppType`/`@CppHeader` on a declaration they do
not apply to, an argument that is not a string literal, a C++ name that is not a valid identifier, a header that
is not a plain file path, a `@CppType` that is not one of the accepted types or does not fit the Dart type, or a
`@CppRange` that is not on an integer binding parameter, whose bounds are not integer literals, are reversed, or lie
outside the parameter's C++ type. All
problems with one member are listed in one diagnostic.

```dart
import 'package:unodar/unodar.dart';

@CppClass('Adafruit_BMP280')
final class Bmp280 {
  int address = 0x76;
  external Bmp280();
  external double readTemperature([int retries = 1]);
}

void setup() {}

void loop() {}
```

```text
input.dart:5:3: error[E017]: a binding class cannot have a field ('address'). Only an external constructor and external methods are allowed.
  = help: Remove it; the C++ object keeps its own state.
input.dart:7:19: error[E017]: unsupported binding method 'readTemperature': it has optional positional parameters.
  = help: Make each parameter required, or named with a constant default value, e.g. `{int retries = 1}`.
```

(Golden tests: `test/golden/e017_binding_members`, `e017_binding_signatures`, `e017_annotations`,
`e017_cpp_range`.)

## E018: Bound object misuse

A binding type (`Servo`, `TwoWire`, your own `@CppClass`) may only be the type of a top-level `final` variable
initialized by its constructor, or of an `external final` object. Its methods are the only thing you can use: a
local, parameter, or return value of a binding type, a non-`final` or `const` bound object, an initializer that is
not the class's constructor, assigning, comparing, or passing the object as a value are all rejected. The C++
object is a global, allocated once and statically; anything else would need copies, references, or the heap.
Uses of a declaration that was already rejected are not reported again.

```dart
import 'package:unodar/unodar.dart';

var servo = Servo();

void center(Servo s) {
  s.write(90);
}

void setup() {}

void loop() {}
```

```text
input.dart:3:5: error[E018]: the bound object 'servo' must be declared `final`.
  = help: Write `final servo = Servo();`. C++ objects are created once, as global variables.
input.dart:5:13: error[E018]: a parameter of the binding type 'Servo' is not supported. Bound objects can only be top-level `final` variables.
  = help: Use the top-level object directly instead of passing it around.
```

(Golden tests: `test/golden/e018_bound_object_declarations`, `e018_bound_object_uses`.)

## E019: `cpp()` misuse

`cpp('…')` must be a statement of its own (or the body of a `void` `=>` function) with exactly one string literal
argument: no interpolation, no variables. It cannot be used in an expression, a `for` loop's initializer or update,
or as a value.

```dart
import 'package:unodar/unodar.dart';

const int pin = 13;

void setup() {
  cpp('pinMode($pin, OUTPUT);');
}

void loop() {
  for (int i = 0; i < 3; cpp('delay(1);')) {}
}
```

```text
input.dart:6:7: error[E019]: the argument of cpp() must be a string literal without interpolation.
  = help: Write the C++ text out in full, e.g. `cpp('pinMode(13, OUTPUT);');`.
input.dart:10:26: error[E019]: cpp() can only be used as a statement of its own.
  = help: Move it to its own line, e.g. into the loop body.
```

(Golden tests: `test/golden/e019_cpp_argument`, `e019_cpp_position`.)

## E020: Heap allocation in `cpp()`

Generated code never uses the heap: the Uno has 2 KB of RAM, and fragmentation fails silently. The text of a
`cpp('…')` statement is therefore rejected if it contains, as a whole word, `new`, `delete`, `malloc`, `calloc`,
`realloc`, `free`, or `String` (Arduino's heap-allocated string class). The check is by word, so it also applies
inside C++ comments and string literals.

```dart
import 'package:unodar/unodar.dart';

void setup() {}

void loop() {
  cpp('char *buffer = (char *) malloc(16);');
}
```

```text
input.dart:6:7: error[E020]: the C++ text uses 'malloc', which allocates on the heap. Generated code must not use the heap.
  = help: Allocate statically instead, e.g. a global array: `cpp('static char buffer[16];');`.
```

(Golden tests: `test/golden/e020_cpp_heap`.)

## E021: Widget program shape

A widget program has `main()` and no `setup()`/`loop()`; a sketch with `setup()`/`loop()` has no widgets and no
signals (`Signal`, `Computed`, `Watch`: changes are delivered by the generated `loop()`, so they would never be). Also
rejected: `runDevice` anywhere but `main()`; a `Device` whose `board` is not `Uno()` or whose `children` is not a
list literal of widgets (no spreads, collection `if`/`for`, or other values); a `serialBaud:` that is not a
compile-time constant (a negative one is E004); and `Serial.begin` in a widget program, because the generated
`setup()` opens the port (set the speed with `Device(serialBaud: …)`).

```dart
import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void main() => runDevice(Device(board: Uno(), children: [led]));

void loop() {}
```

```text
input.dart:7:6: error[E021]: a widget program cannot also declare 'loop()': main() and runDevice() generate setup() and loop().
  = help: Remove it and put the code in widget callbacks, e.g. `Every(Duration(milliseconds: 100), () { … })`.
```

(Golden tests: `test/golden/e021_main_and_loop`, `e021_widgets_without_main`, `e021_device_arguments`,
`e021_device_children`, `e021_serial_begin`.)

## E022: Widget rules

A widget (`Led`, `Button`, `Every`) is a top-level `final` or is written directly inside `Device(children: […])`;
anywhere else (a local variable, inside a callback, a non-`final` variable) it is rejected. Its arguments are
compile-time constants: the pin like any constant, the interval a `Duration(…)` with constant arguments adding up
to a whole number of milliseconds from 1 to 2147483647. Each pin belongs to one widget. Every top-level widget is
listed in `children` exactly once, or it would never be set up and polled. A top-level widget's callback may only
use widgets declared above it. A widget handle can only be listed in `children` or used to call its methods
(`led.toggle()`); it cannot be stored, compared, or passed. `Watch` is a widget and follows all of these rules. A
`Led` bound to a signal (`Led(pin: 13, on: flag)`) is driven only by that signal, so calling `on()`, `off()`,
`toggle()` or `set()` on it is rejected.

```dart
import 'package:unodar/unodar.dart';

int ledPin = 13;
final led = Led(pin: ledPin);
final alarm = Led(pin: 2);
final button = Button(pin: 2, onPressed: () {
  alarm.on();
});

void main() => runDevice(Device(board: Uno(), children: [led, button]));
```

```text
input.dart:4:17: error[E022]: the pin of Led must be a compile-time constant.
  = help: Use a literal or a `const`, e.g. `const int ledPin = 13;`.
input.dart:5:7: error[E022]: the widget 'alarm' is not listed in Device.children, so it would never be set up or polled.
  = help: Add `alarm` to `children: [...]` in main().
input.dart:6:23: error[E022]: pin 2 is already used by 'alarm' (line 5).
  = help: Give each widget its own pin.
```

(Golden tests: `test/golden/e022_constant_arguments`, `e022_pins`, `e022_children`, `e022_placement`,
`e022_declaration_order`, `e022_handle_uses`, `e022_durations`.)

## E023: `delay()` in a widget callback

Widget callbacks run inside the generated `loop()`, which polls every button and timer. `delay()` would stop all of
them while it waits, so it is rejected in a callback (including a `Watch` callback), and in any of your functions that a callback calls, directly
or through other functions. Plain `setup()`/`loop()` sketches keep `delay()`.

```dart
import 'package:unodar/unodar.dart';

final led = Led(pin: 13);

void blink() {
  led.on();
  delay(100);
  led.off();
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Button(pin: 2, onPressed: () {
            blink();
          }),
        ],
      ),
    );
```

```text
input.dart:7:3: error[E023]: 'delay()' runs inside a widget callback (Button's onPressed → blink()), where it would stop every button and timer while it waits.
  = help: Time things with an Every widget instead, keeping state in a top-level variable between ticks.
```

(Golden tests: `test/golden/e023_delay_direct`, `e023_delay_indirect`.)

## E024: Signal misuse

A signal (`Signal`, `Computed`) is a top-level `final` initialized by its constructor, and it is used only through
`.value`. Rejected: a non-`final` or `const` signal, a signal created anywhere else (a local, a callback), a signal
used as a value (stored in another variable, compared, passed, printed, returned), a local, parameter or return
value of a signal type, and a `Watch` whose first argument is not the name of a top-level signal. The C++ signal is
a global, allocated once; anything else would need references or the heap. Uses of a declaration that was already
rejected are not reported again, and a signal used as a value is not also E009.

```dart
import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
var total = Signal<int>(0);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Button(
              pin: 2,
              onPressed: () {
                Serial.println(count);
              }),
        ],
      ),
    );
```

```text
input.dart:4:5: error[E024]: the signal 'total' must be declared `final`.
  = help: Write `final total = Signal<int>(0);`. Signals are created once, as global variables.
input.dart:13:32: error[E024]: the signal 'count' is used as a value; a signal can only be read or written through `.value`.
  = help: Write `count.value`.
```

(Golden tests: `test/golden/e024_signal_declarations`, `e024_signal_uses`, `e024_watch_source`.)

## E025: Reactive cycle

A `Watch` callback writes, directly or through functions it calls, the signal it watches, or a signal whose Watches
lead back to it (`Watch(a)` writes `b`, `Watch(b)` writes `a`). Changes are delivered once per `loop()` pass, so such
a program would deliver on every pass for ever. Each cycle is reported once, at its first write in source order,
with the path from the Watch.

```dart
import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

void bump(int v) {
  count.value = v + 1;
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(count, (v) {
            bump(v);
          }),
        ],
      ),
    );
```

```text
input.dart:6:3: error[E025]: this write closes a cycle: Watch(count) → bump() → count, so the Watch would run again after every delivery.
  = help: Write 'count' where the change starts, e.g. in a Button callback, or derive the value with a Computed.
```

(Golden tests: `test/golden/e025_self_write`, `e025_cycle`, `e025_indirect`.)

## E026: `Computed` rules

The closure of a `Computed` is a single `=>` expression over `.value` of signals and Computeds declared above it,
literals, constants, `Uint8(…)`/`Uint16(…)`/`Int16(…)`, and the subset's operators. Rejected: a block body, any
call (including `analogRead`), an assignment, a mutable top-level variable (the Computed would not see it change),
and a signal or Computed declared below it (which is also what rules out cycles).

```dart
import 'package:unodar/unodar.dart';

int offset = 5;
final count = Signal<int>(0);
final total = Computed(() => count.value + offset);
final twice = Computed(() => later.value * 2);
final later = Signal<int>(0);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(total, (v) {
            Serial.println(v);
          }),
        ],
      ),
    );
```

```text
input.dart:5:44: error[E026]: a Computed can only read signals and Computeds declared above it, and constants; 'offset' is a mutable variable, so the Computed would not see it change.
  = help: Make 'offset' a Signal, or a `const`.
input.dart:6:30: error[E026]: a Computed can only read signals and Computeds declared above it; 'later' is declared on line 7.
  = help: Move the declaration of 'later' above 'twice'.
```

(Golden tests: `test/golden/e026_computed_body`, `e026_computed_reads`.)
