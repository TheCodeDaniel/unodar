# Phase 5 plan — Signals

**Status: approved (2026-11-14), on the `phase-5` branch.** The maintainer approved D1–D7 as recommended (D6 is
PRD §13.3), so `Computed` is in scope (steps 10–11). Step 1 (plan) and step 2 (spec) are done. Phase 6 (classes,
library wrappers) is out of scope.

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

## 5. Memory and flash cost (estimates; measured and recorded in step 12)

AVR has 1-byte alignment, so objects have no padding. Sizes are `static_assert`ed in the runtime test sketch, as for
Phase 4's Led 2 B, Button 7 B, Every 8 B.

| Object | RAM | Flash (estimate, `-Os`) |
|---|---|---|
| `Signal<int>`, `Signal<double>` | **5 B** (value 4 + changed 1) | Write site ~30–40 B (4-byte compare, store, flag); read ~4–8 B |
| `Signal<Uint16>`, `Signal<Int16>` | **3 B** | Write site ~20 B |
| `Signal<bool>`, `Signal<Uint8>` | **2 B** | Write site ~12–16 B |
| `Watch` | **0 B** (no object: a generated function and a branch) | ~10–20 B per Watch plus its body |
| `Led(on: …)` | **0 B** extra (the Led keeps its 2 B) | ~10 B per bound Led |
| `Computed<T>` | **as `Signal<T>`** (last delivered value + flag) | Its compute function, ~10 B per read site, ~20–30 B in delivery |
| `unodar_deliver()` | 0 B static (flags and values are locals) | ~20 B base + ~15–25 B per observed signal |

A signal with no observers gets no delivery code (it keeps its flag byte). Estimate for the goal program: RAM about
the `widget_button` golden's 208 B + 7 B for two signals; flash about 2662 B + 300–400 B. Alternative: pack the
changed flags into bit fields, saving up to 7 bits per signal. Cost: bit operations at every write and take, more
flash; not worth it below dozens of signals.

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
| 12 | Size-budget review (dedicated commit): every Phase 5 budget, RAM per signal golden, the §5 estimates replaced by measurements | `size_budgets.dart` |
| 13 | `examples/counter` (the goal program) with `wokwi/` (two buttons, the L LED, serial monitor), built by `tool/check_arduino.sh` | avr8js on the goal program: bounced presses on D2 and D3, exact serial transcript (`0`, `1`, `2`, `0`; clear at 0 prints nothing) and pin-13 log; negative control |
| 14 | Final docs pass (README status and known limits, PRD status, PLAN); full check suite; end report | — |

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
