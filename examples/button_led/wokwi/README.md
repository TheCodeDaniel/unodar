# Running button_led in Wokwi (no hardware needed)

Each click on the green button toggles the Uno's built-in LED (marked **L**), and the serial monitor shows `tick`
every 500 ms. Wokwi's push button simulates contact bounce, so this also shows the 50 ms debounce at work: one click
is one toggle.

The diagram wires the button between pin 2 and GND (the sketch uses the internal pull-up, so no resistor) and the
Uno's serial port to Wokwi's serial monitor. The generated `setup()` opens the port at 9600 baud, the default of
`Device(serialBaud: …)`.

## Option A: wokwi.com (browser, nothing to install)
1. From the repo root: `dart run packages/unodar_compiler/bin/unodar.dart build examples/button_led/main.dart -o out`
   This writes two files: `out/main/main.ino` and `out/main/unodar_widgets.h` (the widget runtime).
2. Open <https://wokwi.com/projects/new/arduino-uno>.
3. Replace the contents of `sketch.ino` with `out/main/main.ino`.
4. Add the runtime: click the file tab menu (▾ next to the tabs), choose **New file…**, name it `unodar_widgets.h`,
   and paste the contents of `out/main/unodar_widgets.h`.
5. Replace `diagram.json` with [`diagram.json`](diagram.json) from this folder (it adds the button and opens the
   serial monitor).
6. Press ▶. `tick` appears twice a second; click the button to toggle the LED.

Note: wokwi.com builds the sketch with its own default flags. unodar's 32-bit `int` semantics also rely on
`-fwrapv` (docs/SUBSET.md "Building"); this sketch never overflows (the widget runtime compares time as `uint32_t`
on its own), so it behaves the same, but Option B builds it exactly as unodar specifies.

## Option B: Wokwi for VS Code
1. Build as above, then compile to firmware next to this file, with unodar's build properties:
   ```sh
   arduino-cli compile --fqbn arduino:avr:uno \
     --build-property compiler.c.extra_flags=-fwrapv \
     --build-property compiler.cpp.extra_flags=-fwrapv \
     --build-property compiler.c.elf.extra_flags=-fwrapv \
     --output-dir examples/button_led/wokwi/build out/main
   ```
   arduino-cli compiles every file in `out/main`, so `unodar_widgets.h` is picked up with `main.ino`.
2. Open `examples/button_led/wokwi/diagram.json` in VS Code and run **Wokwi: Start Simulator**.
3. Click the button in the simulator; the serial monitor in VS Code's terminal panel shows `tick`.
