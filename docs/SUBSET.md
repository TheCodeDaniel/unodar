# Unodar Dart subset — Phase 2 (language core, experimental)

This is the **exact** list of what the compiler accepts. Anything not listed here is rejected with a diagnostic
(see [`DIAGNOSTICS.md`](DIAGNOSTICS.md)). The subset grows phase by phase; this file is updated *before* any new
syntax is accepted.

**Fidelity rule.** Generated C++ behaves exactly like the Dart source, or the construct is rejected. The only
exceptions are listed under [Known deviations from Dart](#known-deviations-from-dart); each one is a deliberate,
documented decision (see `DECISIONS.md`).

## A complete valid program

```dart
import 'package:unodar/unodar.dart';

const int ledPin = 13;
int extra = 0;

void pulse(int ms) {
  digitalWrite(ledPin, HIGH);
  delay(ms);
  digitalWrite(ledPin, LOW);
  delay(150);
}

int pulseLength(int i) => i % 2 == 0 ? 150 : 450;

void setup() {
  pinMode(ledPin, OUTPUT);
}

void loop() {
  for (int i = 0; i < 3; i++) {
    pulse(pulseLength(i));
  }
  if (extra >= 3) {
    extra = 0;
  } else {
    extra += 1;
  }
  delay(1000);
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

Every other type is rejected (E009), including nullable types (`int?`), `num`, `dynamic`, `Object`, `String`,
function types, and classes. That includes the *inferred* static type of an expression: `flag ? 1 : 2.5` has type
`num` in Dart and is rejected.

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
| `void setup()`, `void loop()` | Both required. Exactly `void name() { … }` (E006). | Same |
| Functions | `R name(T a, T b) { … }` or `=> expr;`. `R` is a supported type or `void`; every parameter is required, positional, and has an explicit supported type. Recursion, direct or mutual, is rejected (E016). | Same, plus a prototype for each function |
| `const` variables | `const int x = …;` or `const x = …;` (type inferred). | `constexpr int32_t x = …;` |
| `final` variables | As above with `final`. | `const int32_t x = …;` |
| Mutable variables | `int x = …;` or `var x = …;`. | `int32_t x = …;` |

**Top-level initializers** are required and must be compile-time constant expressions (E015): literals, unodar
constants (`HIGH`, …), `const` variables declared **above** this one, `Uint8(…)`/`Uint16(…)`/`Int16(…)` of
constants, and the operators below. A `final` or mutable variable is not a constant, even if its initializer is.

Still rejected: `main()` (E008); classes, enums, mixins, extensions, typedefs, top-level getters/setters (E005);
`late`/`external` variables (E005); optional, named, or default parameters, type parameters, `async`/generators,
`external` functions, untyped parameters (E011).

## Statements

Allowed inside any function body:

| Statement | Notes |
|---|---|
| Call | `pulse(300);`, `delay(ms);`. A non-void result may be discarded. |
| Assignment | `x = e;`, `x += e;`, `x -= e;`, `x++;`, `x--;`, `++x;`, `--x;`. **Statements only**: an assignment, `++`, or `--` inside a larger expression is rejected (E002). `*=`, `/=`, `~/=`, `%=` and the bitwise forms are rejected (E002); write `x = x * y;`. |
| Local variable | `int x = e;`, `var x = e;`, `final x = e;`, `const x = e;`, `int x;`. Any initializer expression. Types are the resolved Dart types. `const` → `constexpr`, `final` → `const`. `late` is rejected. |
| `if` / `else` | Including `else if` chains. |
| `while` | |
| `for` | C-style: `for (init; condition; updates)`, each part optional. Updates follow the assignment rule. |
| `return` | `return;` or `return e;`. |
| `break`, `continue` | Unlabeled only. |
| Nested block | `{ … }` |

Rejected (E002): `do`/`while`, `switch`, `for`-`in`, labeled statements and labeled `break`/`continue`, `try`,
`throw`, `assert`, `yield`, empty statements (`;`), pattern declarations. Local functions are E012.

## Expressions

| Construct | Rule | C++ |
|---|---|---|
| Integer literals | Decimal or hex, at most 2147483647 (E010). Write `-2147483647 - 1` for the minimum. | Decimal, plus an `L` suffix only where needed (see below) |
| Double literals | At most the `float` maximum (≈3.4e38, E010). An integer literal in a `double` context (`double d = 1;`) is a double. | `1.0f`, `3.5f`, `1e-7f` |
| Bool literals | `true`, `false` | Same |
| Names | Locals, parameters, top-level variables, unodar constants. | Same name |
| Parentheses | Kept where C++ needs them; see Precedence. | |
| Unary | `-x`, `!b` | Same |
| Arithmetic | `+`, `-`, `*` on numbers. | Same |
| `~/` | Integer division, truncating toward zero. `int` operands only. | `/` (also truncates toward zero) |
| `/` | On ints or doubles; the result is a `double`, as in Dart. | `float(a) / float(b)` for ints |
| `%` | `int` operands only. **Dart semantics**: the result is never negative (`-7 % 2 == 1`). | `unodar_mod(a, b)`, a 3-line `constexpr` helper emitted only when used |
| Comparison | `==`, `!=`, `<`, `<=`, `>`, `>=`. Both sides numbers, or (for `==`/`!=`) both bools; anything else is E009, because `true == 1` is false in Dart and true in C++. | Same |
| Logical | `&&`, `\|\|` (short-circuit) | Same |
| Conditional | `c ? a : b`, where the result has a supported type. | Same |
| Calls | Functions declared in this file, and unodar API functions, with positional arguments. | Same |
| Sized constructors | `Uint8(e)`, `Uint16(e)`, `Int16(e)` | `uint8_t(e)` etc. |

Rejected: `%` and `~/` on doubles, bitwise and shift operators (`& | ^ ~ << >> >>>`), `??`, `is`/`as`, method and
property access such as `x.abs()` or `x.isEven` (E003 / E002), strings, `null`, collection literals, cascades,
`throw`, `await` (E002); closures and function references such as passing `pulse` without calling it (E012).

### Integer arithmetic is always 32-bit

On the Uno, C++ `int` is 16 bits, so plain C++ `60 * 1000` wraps to -5536. Unodar guarantees that every `int`
operation is computed in `int32_t`: when *both* operands would otherwise be narrower in C++, the emitter widens one
of them, with an `L` suffix on a literal (`60L * 1000`) or `int32_t(x)` otherwise (e.g. two `Uint16` values).

### Constant expressions are checked

Any subexpression made only of constants (literals, unodar constants, `const` variables) is evaluated at compile
time with Dart semantics. If any intermediate value leaves the `int32_t` range, or it divides by zero with `~/`,
`%`, or `/` on ints, it is rejected (E010). `delay(60 * 60 * 1000 * 1000)` is an error, not a silent wrap.

### Precedence

The C++ is printed from the expression tree that Dart parsed, with parentheses inserted wherever C++ precedence or
associativity would otherwise regroup it: `a - (b - c)` keeps its parentheses, `(a + b) * c` keeps them,
`- -x` is never printed as `--x`. Redundant parentheses may be dropped.

### Evaluation order

Dart evaluates operands and arguments strictly left to right. C++ does not fix the order for the operands of most
operators or for call arguments. So where the order could matter, unodar rejects the code (E013): within one
operator's operands, one call's argument list, or the two sides of `+=`/`-=`, a call to a user function may not sit
next to another call or next to a read of a mutable top-level variable. `&&`, `||`, and `?:` are always fine.
Fix: store the call's result in a local variable first.

## Names

User declarations (top-level variables, functions, parameters, locals) may not use a name that would collide with
C++ or the Arduino core (E014):

- C++ keywords, including the alternative operator names that are valid Dart identifiers (`and`, `or`, `not`, …).
- Every unodar API name (`pinMode`, `delay`, `HIGH`, …), taken from the compiler's API registry.
- A deny-list of Arduino core and avr-libc functions and macros (`min`, `max`, `abs`, `round`, `sq`, `map`,
  `constrain`, `bit`, `word`, `byte`, `millis`, `init`, `sin`, `sqrt`, …). The full list lives in the target
  (`UnoTarget.reservedNames`).
- ALL-CAPS names (no lower-case letter): the AVR headers define hundreds of macros such as `PORTB`. Dart style
  already prefers `ledPin` over `LED_PIN`.
- Names ending in `_t`, containing `__` or `$`, starting with `_` and an upper-case letter, or starting with
  `unodar_` (reserved for generated helpers).

## Recursion

A function may not call itself, directly (`f` calls `f`) or through other functions (`ping` calls `pong` calls
`ping`), E016. The compiler builds the call graph of all user functions, including `setup` and `loop`, and rejects
every cycle. Reason: the Uno has a 2 KB stack and no overflow check, so where Dart throws `StackOverflowError`,
the board would silently overwrite its global variables. Rewrite recursion as a loop.

## Calling the unodar API

| Function | Arduino C++ parameters |
|---|---|
| `pinMode(pin, mode)` | `uint8_t pin, uint8_t mode` |
| `digitalWrite(pin, value)` | `uint8_t pin, uint8_t val` |
| `delay(ms)` | `unsigned long ms` |

Arguments may be any supported `int` expression. A **constant** argument outside the Arduino parameter's range is
rejected (E004), e.g. `digitalWrite(-13, HIGH)`. Non-constant values are converted to the Arduino parameter type
(see deviations). The constants `HIGH`, `LOW`, `OUTPUT`, `INPUT`, `INPUT_PULLUP` are ordinary `int` constants usable
in any expression. No API function has named parameters yet; the registry models them, but they are enabled in
Phase 3. A named argument is E004 (today the analyzer already reports it first, as E007).

## Translation and layout

The generated file contains, in order: the `// Generated by unodar…` header, `#include <Arduino.h>`, any helpers the
program uses (`unodar_mod`), a prototype for every user function except `setup`/`loop`, the top-level variables in
source order, then the functions in source order. A `#line` directive precedes every variable, function, and
statement. Output is deterministic: the same input gives byte-identical output on any machine.

## Known deviations from Dart

These are the only places where generated C++ can behave differently from the same Dart program. They are runtime
conditions that cannot be detected at compile time; constant cases are rejected (E010).

| Situation | Dart | Generated C++ |
|---|---|---|
| `int` overflow at runtime (a result outside -2147483648…2147483647, including `-x`, `x ~/ -1`, and `x % -1` for the minimum value) | Exact 64-bit result | **Undefined behaviour** (C++ signed overflow). In practice it usually wraps, but the compiler may assume it never happens. Keep values in range. |
| Integer `~/` or `%` by a variable that is zero | Throws `IntegerDivisionByZeroException` | **Undefined**; on AVR the program continues with a meaningless result. No check is inserted. |
| `double` precision and range | 64-bit (≈15–17 digits, max ≈1.8e308) | 32-bit `float` (≈6–7 digits, max ≈3.4e38). An `int` mixed with a `double`, or divided with `/`, converts to `float` and keeps only 24 bits of precision (exact up to 16777216). |
| A non-constant value passed to an Arduino function outside its parameter type | (external) | Converted to the C++ parameter type by C++ rules, e.g. `delay(-1)` waits about 49 days, a pin of 300 becomes 44. |

## Diagnostics summary

| Construct | Code |
|---|---|
| Missing `setup()` or `loop()` | E001 |
| Unsupported statement, operator, or expression form | E002 |
| Call to a function that is neither declared in this file nor a unodar API function (incl. `Serial.println`, `x.abs()`) | E003 |
| Constant argument out of range for an Arduino parameter; named argument | E004 |
| Classes, enums, typedefs, extensions, getters/setters, `late`/`external` variables, other imports, `export`/`part` | E005 |
| `setup`/`loop` not exactly `void name() { … }` | E006 |
| Any Dart analysis error | E007 |
| `main()` | E008 |
| Unsupported or nullable type; comparing a bool with a number | E009 |
| Constant out of range, constant overflow, constant division by zero | E010 |
| Optional/named/default parameters, generics, `async`, untyped parameters in a user function | E011 |
| Closures, function references, local functions | E012 |
| Code whose meaning depends on evaluation order | E013 |
| Name that collides with C++ or Arduino | E014 |
| Top-level initializer that is not a compile-time constant | E015 |
| A function that calls itself, directly or through other functions | E016 |
| Strings, `Serial`, widgets, `Signal`, classes, interop annotations, `cpp()` | not yet available |
