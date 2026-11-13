// The static widget tree (docs/SUBSET.md "Widgets: runDevice").
//
// The compiler reads the tree written in `main()` statically and never runs it: each widget becomes a global C++
// object from `unodar_widgets.h`, each callback a plain function, and `runDevice` a generated `setup()` and
// `loop()`. Constructors are `external` and not `const`, so there is exactly one way to write a widget.

/// Runs [device]: the compiler turns this call into the program's `setup()` and `loop()`.
///
/// Only as the single statement of `main()`: `void main() => runDevice(Device(board: Uno(), children: [...]));`.
external void runDevice(Device device);

/// The device: a [board] and the widgets that run on it.
///
/// [children] is a list literal of widgets, each a top-level `final` (`final led = Led(pin: 13);`) or written
/// directly in the list. Their order is the order in which `setup()` starts them and `loop()` polls them.
///
/// If the program uses `Serial`, the generated `setup()` opens it at [serialBaud] bits per second before anything
/// else; a widget program does not call `Serial.begin` itself.
final class Device {
  external Device({required Board board, required List<Widget> children, int serialBaud = 9600});
}

/// A microcontroller board. [Uno] is the only board in this version.
abstract final class Board {}

/// The Arduino Uno (ATmega328P).
final class Uno extends Board {
  external Uno();
}

/// Something on the board that the generated `loop()` drives: [Led], [Button], [Every].
abstract final class Widget {}

/// An LED (or any output) on [pin] (0–19: D0–D13, A0–A5). It starts off (LOW).
///
/// Declare it as a top-level `final` to switch it from callbacks: `final led = Led(pin: 13);`.
final class Led extends Widget {
  external Led({required int pin});

  /// Switches the LED on (HIGH).
  external void on();

  /// Switches the LED off (LOW).
  external void off();

  /// Switches the LED on if it is off, and off if it is on.
  external void toggle();
}

/// A push button on [pin] (0–19), wired between the pin and GND (the internal pull-up is used, no resistor).
///
/// [onPressed] runs once per press: when the reading changes from HIGH to LOW and stays there for 50 ms
/// (debounced). Releasing runs nothing, and a button already held at power-up is not a press. The callback is a
/// closure without parameters, `() { … }`; it must not call `delay()`.
final class Button extends Widget {
  external Button({required int pin, required void Function() onPressed});
}

/// Runs [callback] every [interval], the first time one interval after `setup()`.
///
/// [interval] is a constant `Duration` of a whole number of milliseconds, from 1 ms to 2147483647 ms. The timing is
/// drift-free and survives the `millis()` wrap; if callbacks fall behind, missed ticks run on the following
/// `loop()` passes, one per pass. The callback is a closure without parameters; it must not call `delay()`.
final class Every extends Widget {
  external Every(Duration interval, void Function() callback);
}
