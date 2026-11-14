# Running counter in Wokwi (no hardware needed)

The green **+1** button counts up, the red **clear** button sets the count back to 0. The serial monitor prints `0`
at start and then every new count; the Uno's built-in LED (marked **L**) is lit while the count is odd. Pressing
**clear** when the count is already 0 prints nothing: writing an equal value to a signal delivers nothing.
Wokwi's push buttons simulate contact bounce, so this also shows the 50 ms debounce: one click is one count.

The diagram wires each button between its pin (2 and 3) and GND (the sketch uses the internal pull-ups, so no
resistors) and the Uno's serial port to Wokwi's serial monitor. The generated `setup()` opens the port at 9600 baud,
the default of `Device(serialBaud: …)`, and ends by delivering every signal's initial value.

## Option A: wokwi.com (browser, nothing to install)
1. From the repo root: `dart run packages/unodar_compiler/bin/unodar.dart build examples/counter/main.dart -o out`
   This writes two files: `out/main/main.ino` and `out/main/unodar_widgets.h` (the widget and signal runtime).
2. Open <https://wokwi.com/projects/new/arduino-uno>.
3. Replace the contents of `sketch.ino` with `out/main/main.ino`.
4. Add the runtime: click the file tab menu (▾ next to the tabs), choose **New file…**, name it `unodar_widgets.h`,
   and paste the contents of `out/main/unodar_widgets.h`.
5. Replace `diagram.json` with [`diagram.json`](diagram.json) from this folder (it adds both buttons and opens the
   serial monitor).
6. Press ▶. `0` appears; click **+1** and **clear**.

Note: wokwi.com builds the sketch with its own default flags. unodar's 32-bit `int` semantics also rely on
`-fwrapv` (docs/SUBSET.md "Building"); this sketch only overflows after 2147483647 presses, so it behaves the same,
but Option B builds it exactly as unodar specifies.

## Option B: Wokwi for VS Code
1. Build as above, then compile to firmware next to this file, with unodar's build properties:
   ```sh
   arduino-cli compile --fqbn arduino:avr:uno \
     --build-property compiler.c.extra_flags=-fwrapv \
     --build-property compiler.cpp.extra_flags=-fwrapv \
     --build-property compiler.c.elf.extra_flags=-fwrapv \
     --output-dir examples/counter/wokwi/build out/main
   ```
   arduino-cli compiles every file in `out/main`, so `unodar_widgets.h` is picked up with `main.ino`.
2. Open `examples/counter/wokwi/diagram.json` in VS Code and run **Wokwi: Start Simulator**.
3. Click the buttons in the simulator; the serial monitor in VS Code's terminal panel shows the count.
