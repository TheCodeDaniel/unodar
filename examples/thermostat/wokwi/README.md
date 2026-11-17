# Running thermostat in Wokwi (no hardware needed)

The 16×2 LCD shows the temperature the DHT22 measures (top row, every 2.5 s) and the setpoint and mode (bottom row).
The heater, a red LED on pin 13 (the Uno's **L** LED follows it), switches on when the temperature is below the
setpoint minus 1 and off when it is above the setpoint plus 1. The green **up** and blue **down** buttons move the
setpoint between 5 and 35; it is shown at once and saved in EEPROM. Click the DHT22 to change its temperature: the
diagram starts at 18 °C, so the heater comes on at the first reading.

The diagram wires the LCD in parallel 4-bit mode (RS 12, E 11, D4–D7 on 5, 4, 3, 2, R/W to GND), the DHT22's data
line to pin 8, each button between its pin (6, 7) and GND (internal pull-ups, no resistors), and the LED through a
220 Ω resistor. The program does not use the serial monitor.

## Option A: wokwi.com (browser, nothing to install)
1. From the repo root: `dart run packages/unodar_compiler/bin/unodar.dart build examples/thermostat/main.dart -o out`
   This writes two files: `out/main/main.ino` and `out/main/unodar_widgets.h` (the widget and signal runtime).
2. Open <https://wokwi.com/projects/new/arduino-uno>.
3. Replace the contents of `sketch.ino` with `out/main/main.ino`.
4. Add the runtime: click the file tab menu (▾ next to the tabs), choose **New file…**, name it `unodar_widgets.h`,
   and paste the contents of `out/main/unodar_widgets.h`.
5. Replace `diagram.json` with [`diagram.json`](diagram.json) from this folder.
6. In the **Library Manager** tab, add the three libraries of [`libraries.txt`](libraries.txt): LiquidCrystal,
   DHT sensor library, and Adafruit Unified Sensor (DHT's dependency).
7. Press ▶. After 2.5 s the LCD shows `Temp 18.0` and `Set 21  heating`, and the LED is on. Press **up** a few times,
   or raise the DHT22's temperature, and watch the heater switch off above the setpoint plus 1.

To see the setpoint survive a reset, press the Uno's reset button rather than restarting the simulation, which may
start with a fresh EEPROM. (The test suite checks the reset in avr8js: a second run on the same EEPROM shows the saved
setpoint and writes nothing.)

Note: wokwi.com builds the sketch with its own default flags and library versions. unodar's 32-bit `int` semantics
also rely on `-fwrapv` (docs/SUBSET.md "Building"); nothing in this program overflows, but Option B builds it exactly
as unodar specifies, with the pinned libraries.

## Option B: Wokwi for VS Code
1. Build as above, then compile to firmware next to this file, with unodar's build properties:
   ```sh
   arduino-cli compile --fqbn arduino:avr:uno \
     --build-property compiler.c.extra_flags=-fwrapv \
     --build-property compiler.cpp.extra_flags=-fwrapv \
     --build-property compiler.c.elf.extra_flags=-fwrapv \
     --output-dir examples/thermostat/wokwi/build out/main
   ```
   The libraries must be installed at the versions in `tool/arduino_libraries.txt`; `tool/check_arduino.sh` prints
   the install command for any that is missing.
2. Open `examples/thermostat/wokwi/diagram.json` in VS Code and run **Wokwi: Start Simulator**.
3. Click the buttons and the DHT22 in the simulator.
