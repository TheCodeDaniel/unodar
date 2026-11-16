# Phase 6: documentation waiting for its code

`docs_test` runs every example in `docs/DIAGNOSTICS.md` against the current compiler, so an example whose output
changes with a construct moves into the docs in that construct's commit (as in Phase 3, `docs/DECISIONS.md`
2026-11-12). This file holds the final text until then and is deleted when it is empty.

## E005, replaced in step 3 (classes are accepted)

```markdown
## E005: Unsupported top-level declaration

Top-level functions and variables are supported, and so are your own classes and enums (checked by E027 and E028),
binding classes (annotated `@CppClass`, checked by E017) and `external` objects of a binding type. Extensions,
extension types, typedefs, and top-level getters/setters are not, nor are `late` variables or `external` variables
of any other type. Also used for directives: any import other than an unprefixed `package:unodar/unodar.dart`, and
`export`/`part`.
```

with the example

```dart
import 'package:unodar/unodar.dart';

extension Doubled on int {
  int get doubled => this * 2;
}

late int ledPin;

void setup() {}

void loop() {}
```

```text
input.dart:3:1: error[E005]: an extension is not supported in this version. Only top-level functions, variables, classes, enums, and binding classes may be declared.
  = help: Remove this declaration; see docs/SUBSET.md for what may be declared at the top level.
input.dart:7:1: error[E005]: a late variable ('ledPin') is not supported in this version. Only top-level functions, variables, classes, enums, and binding classes may be declared.
  = help: Remove `late` and give the variable a constant initializer.
```
