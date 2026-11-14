// Signals: state that widgets react to (docs/SUBSET.md "Signals").
//
// Like the widgets, these are declarations only: the compiler reads them and generates a statically allocated
// `unodar::Signal<T>` per signal and one flat function that delivers changes. Constructors are `external` and not
// `const`, so there is exactly one way to write a signal.

/// A value that can be watched: a [Signal] (or, from a later step, a `Computed`).
///
/// Pass one to `Watch(signal, (v) { … })` or `Led(pin: …, on: signal)`. Read it through [value].
abstract final class ReadonlySignal<T> {
  /// The current value.
  T get value;
}

/// A value that widgets react to: `final count = Signal<int>(0);`.
///
/// Declare it as a top-level `final` with a constant initial value, in a widget program. `T` is `int`, `double`,
/// `bool`, `Uint8`, `Uint16` or `Int16`. Read and write it only through [value]; a signal itself cannot be stored,
/// compared, passed, or printed.
///
/// Writing a value equal to the current one does nothing. Otherwise the signal is marked changed, and the change is
/// delivered at the end of the current `loop()` pass: every `Watch` of the signal runs once with the latest value,
/// and every `Led` bound to it follows. Several writes in one pass are delivered once. A write made by a `Watch`
/// callback is delivered on the next pass. The initial value is delivered once, at the end of `setup()`.
final class Signal<T> extends ReadonlySignal<T> {
  /// A signal holding [initial], a compile-time constant.
  external Signal(T initial);

  @override
  external T get value;

  /// Writes the value: `count.value = 3;`, `count.value++;`, `count.value += 2;` (statements only).
  external set value(T value);
}
