# Phase 4 pending doc examples

`docs_test` compiles the examples in `docs/` and requires the output shown. These Phase 4 versions describe compiler
behaviour that does not exist yet, so they wait here and replace the Phase 3 text in the commit whose code makes them
true (same approach as Phase 3, `docs/DECISIONS.md`). Delete this file when all of them have moved.

## `docs/DIAGNOSTICS.md`, E008 example

Lands with the `main()`/`runDevice` commit (plan step 6).

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
