# Phase 4 pending doc examples

`docs_test` compiles the examples in `docs/` and requires the output shown. These Phase 4 versions describe compiler
behaviour that does not exist yet, so they wait here and replace the Phase 3 text in the commit whose code makes them
true (same approach as Phase 3, `docs/DECISIONS.md`). Delete this file when all of them have moved.

## `docs/DIAGNOSTICS.md`, E022 example

Lands with the commit that adds the remaining E022 rules (plan step 6d: pins, children, declaration order,
handles); it needs `Button` (6b). Until then the E022 section shows a `Led`-only example.

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

