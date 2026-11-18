# Your first program

This assumes the [quick start](../README.md#quick-start) worked: `unodar new hello` made a project and
`unodar flash` made the LED marked **L** on the board blink.

## 1. What `main.dart` says

```dart
import 'package:unodar/unodar.dart';

final led = Led(pin: LED_BUILTIN);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Every(Duration(milliseconds: 500), () {
            led.toggle();
          }),
        ],
      ),
    );
```

- `Led(pin: LED_BUILTIN)` is the LED on pin 13. A widget is a `final` at the top level, or written straight into
  `children`.
- `Every(…)` runs its callback every 500 ms; the first time 500 ms after the board starts.
- `main()` is read by the compiler, never run: it describes the device. There is no `build()`, no `setState()` and
  no rebuild; widgets are set up once and then polled, thousands of times a second.

`unodar build` shows what this costs: `flash 940 B of 32256 (2 %), RAM 19 B of 2048 (0 %)`. The C++ it generated is
in `build/main/main.ino`; it is meant to be readable.

## 2. Add a button

Put a push button on a breadboard, one leg to **pin 2** and the other to **GND**. No resistor: unodar uses the
pin's internal pull-up. Then replace `main.dart` with:

```dart
import 'package:unodar/unodar.dart';

final led = Led(pin: LED_BUILTIN);
final button = Button(
    pin: 2,
    onPressed: () {
      led.toggle();
    });

void main() => runDevice(Device(board: Uno(), children: [led, button]));
```

and run `unodar flash`. Each press toggles the LED, once per press: unodar debounces the button (the reading must
stay low for 50 ms), so a bouncing contact does not count twice.

No board, or no button at hand? [Wokwi](https://wokwi.com/projects/new/arduino-uno) simulates an Uno in the
browser: `examples/button_led/wokwi/` has the wiring, and its README says which files to paste in.

## 3. Read an error

Try a mistake a Flutter developer makes on day one: in the button program, replace `led.toggle();` with
`print('pressed');`.

`unodar flash` stops before touching the board:

```text
main.dart:7:7: error[E003]: Dart's print() has nowhere to print on the board.
  |
7 |       print('pressed');
  |       ^
  = help: Print over the USB serial port instead, e.g. `Serial.println('hello');`, and read it with a serial monitor (`arduino-cli monitor` or the Arduino IDE).
  = see: https://github.com/TheCodeDaniel/unodar/blob/v0.7.0/docs/DIAGNOSTICS.md#e003-call-to-a-function-that-is-not-part-of-the-supported-unodar-api
```

Every error has a code (`E003`), the line, what to write instead, and a link to its page. Write
`Serial.println('pressed');` instead, flash again, and watch the output with
`~/.unodar/bin/arduino-cli monitor --config-file ~/.unodar/arduino-cli.yaml -p <port>` (the port `flash` printed;
9600 baud is the default). Close the monitor before the next `unodar flash`: it holds the port.

## 4. Where to go from here

- [`SUBSET.md`](SUBSET.md) lists exactly what unodar accepts: types, statements, widgets (`Led`, `Button`, `Every`,
  `Watch`, `OnStart`), signals, your own classes, and the libraries (EEPROM, SPI, SoftwareSerial, LiquidCrystal,
  DHT, Servo, Wire).
- The [`examples/`](../examples) go further: `counter` counts presses with a `Signal`, `thermostat` drives an LCD
  and keeps a setpoint in EEPROM.
- Why some Dart is rejected: a Uno has 2 KB of RAM and no operating system. There is no heap, no garbage collector,
  no event loop and no strings beyond printed literals, and unodar never compiles something that would behave
  differently from your Dart. [`STATUS.md`](STATUS.md) lists the limits.
