# Running dial in Wokwi (no hardware needed)

Turning the potentiometer moves the servo between 0° and 180°, the Uno's built-in LED (marked **L**) lights up past
the halfway mark, and every 500 ms the serial monitor shows a line like

```text
level=512 angle=90 volts=2.502
```

The diagram wires the potentiometer's wiper to A0 (its ends to 5V and GND), the servo's signal to pin 9, and the
Uno's serial port to Wokwi's serial monitor. The sketch opens the port at 115200 baud and prints `dial ready` first.

## Option A: wokwi.com (browser, nothing to install)
1. From the repo root: `dart run packages/unodar_compiler/bin/unodar.dart build examples/dial/main.dart -o out`
2. Open <https://wokwi.com/projects/new/arduino-uno>.
3. Replace the contents of `sketch.ino` with `out/main/main.ino`.
4. Replace `diagram.json` with [`diagram.json`](diagram.json) from this folder (it adds the potentiometer and the
   servo and opens the serial monitor).
5. Add the Servo library: in the **Library Manager** tab click **+** and choose **Servo**, or create a
   `libraries.txt` file with the contents of [`libraries.txt`](libraries.txt).
6. Press ▶. The serial monitor opens below the diagram with `dial ready`; click the potentiometer and drag its knob
   to turn the servo and watch the readings change.

Note: wokwi.com builds the sketch with its own default flags. unodar's 32-bit `int` semantics also rely on
`-fwrapv` (docs/SUBSET.md "Building"); this sketch never overflows, so it behaves the same, but Option B builds it
exactly as unodar specifies.

## Option B: Wokwi for VS Code
1. Build as above, then compile to firmware next to this file, with unodar's build properties (needs
   `arduino-cli lib install Servo@1.3.0` once):
   ```sh
   arduino-cli compile --fqbn arduino:avr:uno \
     --build-property compiler.c.extra_flags=-fwrapv \
     --build-property compiler.cpp.extra_flags=-fwrapv \
     --build-property compiler.c.elf.extra_flags=-fwrapv \
     --output-dir examples/dial/wokwi/build out/main
   ```
2. Open `examples/dial/wokwi/diagram.json` in VS Code and run **Wokwi: Start Simulator**.
3. The serial monitor appears in VS Code's terminal panel (Wokwi opens it because the diagram connects
   `$serialMonitor`). Drag the potentiometer knob in the simulator to move the servo.
