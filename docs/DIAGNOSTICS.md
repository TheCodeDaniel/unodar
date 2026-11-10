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

Inside `setup`/`loop`, Phase 1 accepts only single call statements. Control flow, local variables, `return`, nested blocks, and expression statements other than a call are rejected.

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  if (true) {
    digitalWrite(13, HIGH);
  }
}
```

```text
input.dart:8:3: error[E002]: an if statement is not supported in this version. Only calls to unodar API functions are allowed here.
  = help: Rewrite this as a sequence of pinMode/digitalWrite/delay calls; see docs/SUBSET.md.
```

(Golden test: `test/golden/e002_if_statement`.)

## E003: Call to a function that is not part of the supported unodar API

The call must resolve to `pinMode`, `digitalWrite`, or `delay` declared in `package:unodar`. This includes undefined functions (the analyzer would call this an "undefined name"; unodar reports E003 instead) and your own functions. Calls with a receiver (`Serial.println`) are also E003 when they resolve, or E007 when `Serial` is undefined.

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
input.dart:8:3: error[E003]: unknown function 'tone'. Only pinMode, digitalWrite, and delay are supported in this version.
  = help: Remove this call. More Arduino functions arrive in a later phase; see docs/SUBSET.md.
```

(Golden test: `test/golden/e003_unknown_function`.)

## E004: Unsupported argument

Only non-negative integer literals and the unodar constants `HIGH`, `LOW`, `OUTPUT`, `INPUT`, `INPUT_PULLUP` are allowed. Arguments of a call that already got E003 are not checked.

```dart
import 'package:unodar/unodar.dart';

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(-13, HIGH);
  delay(250 + 250);
}
```

```text
input.dart:8:16: error[E004]: a negative number is not supported as an argument. Only integer literals and unodar constants are allowed.
  = help: Use a literal such as `13` or a constant such as `HIGH`, `LOW`, `OUTPUT`, `INPUT`, `INPUT_PULLUP`.
input.dart:9:9: error[E004]: an arithmetic or logical expression is not supported as an argument. Only integer literals and unodar constants are allowed.
  = help: Use a literal such as `13` or a constant such as `HIGH`, `LOW`, `OUTPUT`, `INPUT`, `INPUT_PULLUP`.
```

(Golden test: `test/golden/e004_non_literal_argument`.)

## E005: Unsupported top-level declaration

Only `void setup()` and `void loop()` may be declared. Also used for directives: any import other than an unprefixed `package:unodar/unodar.dart`, and `export`/`part`.

```dart
import 'package:unodar/unodar.dart';

int ledPin = 13;

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {}
```

```text
input.dart:3:1: error[E005]: a top-level variable ('ledPin') is not supported in this version. Only `void setup()` and `void loop()` may be declared.
  = help: Remove this declaration and inline its use into setup() or loop().
```

(Golden test: `test/golden/e005_top_level_variable`.)

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
