# Phase 3 pending doc examples

`docs_test` compiles three examples in `docs/` and requires the output shown. Their Phase 3 versions describe
compiler behaviour that does not exist yet, so they wait here and replace the Phase 2 text in the commit whose code
makes them true (`docs/DECISIONS.md`, 2026-11-12). Delete this file when all three have moved.

## `docs/SUBSET.md`, "A complete valid program"

Lands with the last feature it uses (the Servo golden, plan step 5).

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

## `docs/DIAGNOSTICS.md`, E003 example output

Lands with the new E003 wording, in the `cpp()` commit (plan step 5, last construct), since its help points to
`cpp()`. Until then the E003 message keeps listing the API functions.

```text
input.dart:8:3: error[E003]: unknown function 'tone': it is neither declared in this file nor part of the unodar API.
  = help: Declare the function in this file, or call the Arduino function through the escape hatch, e.g. `cpp('tone(8, 440);');`. See docs/SUBSET.md for the unodar API.
```

## `docs/DIAGNOSTICS.md`, E005 example output

Lands with the `@CppClass` relaxation of E005 (plan step 5, user bindings).

```text
input.dart:3:1: error[E005]: a class without @CppClass is not supported in this version. Only top-level functions, variables, and binding classes may be declared.
  = help: Remove this declaration, or annotate it with `@CppClass('CppName')` if it describes a C++ class; see docs/SUBSET.md.
input.dart:5:1: error[E005]: a late variable ('ledPin') is not supported in this version. Only top-level functions, variables, and binding classes may be declared.
  = help: Remove `late` and give the variable a constant initializer.
```
