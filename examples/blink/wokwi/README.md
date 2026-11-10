# Running blink in Wokwi (no hardware needed)

The Uno's built-in LED (marked **L**) and an external red LED on pin 13 should blink every 500 ms.

## Option A: wokwi.com (browser, nothing to install)
1. From the repo root: `dart run packages/unodar_compiler/bin/unodar.dart build examples/blink/main.dart -o out`
2. Open <https://wokwi.com/projects/new/arduino-uno>.
3. Replace the contents of `sketch.ino` with `out/main/main.ino`.
4. Optional: replace `diagram.json` with [`diagram.json`](diagram.json) from this folder to add the external LED.
5. Press ▶. The LED blinks.

## Option B: Wokwi for VS Code
1. Build as above, then compile to firmware next to this file:
   `arduino-cli compile --fqbn arduino:avr:uno --output-dir examples/blink/wokwi/build out/main`
2. Open `examples/blink/wokwi/diagram.json` in VS Code and run **Wokwi: Start Simulator**.
