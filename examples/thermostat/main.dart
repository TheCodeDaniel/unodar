// Thermostat: the Phase 6 goal program. A DHT22 measures the temperature every 2.5 s; the heater (an LED on pin 13)
// switches on below the setpoint minus the hysteresis and off above the setpoint plus it. Two push buttons move the
// setpoint between 5 and 35 degrees, a 16x2 LCD shows the temperature, the setpoint and the mode, and the setpoint is
// kept in EEPROM, so it survives a reset. If a reading fails, the LCD says so and the heater goes off.
//
// Wiring: LCD (parallel, 4-bit) RS 12, E 11, D4-D7 on 5, 4, 3, 2, R/W to GND; DHT22 data on pin 8; push buttons
// between pin 6 and GND (up) and pin 7 and GND (down); the heater LED on pin 13 (the Uno's L LED, or one with a
// resistor).
// Build:   dart run packages/unodar_compiler/bin/unodar.dart build examples/thermostat/main.dart -o out
//          (writes out/main/main.ino and out/main/unodar_widgets.h; arduino-cli compiles the folder)
import 'package:unodar/dht.dart';
import 'package:unodar/eeprom.dart';
import 'package:unodar/liquid_crystal.dart';
import 'package:unodar/unodar.dart';

enum Mode { idle, heating }

class Thermostat {
  final int hysteresis;
  Mode mode = Mode.idle;

  Thermostat({this.hysteresis = 1});

  void update(double temperature, int target) {
    if (mode == Mode.idle && temperature < target - hysteresis) {
      mode = Mode.heating;
    } else if (mode == Mode.heating && temperature > target + hysteresis) {
      mode = Mode.idle;
    }
  }

  bool get heating => mode == Mode.heating;
}

const int setpointAddress = 0;
const int lowest = 5;
const int highest = 35;

final setpoint = Signal<int>(21);
final thermostat = Thermostat(hysteresis: 1);
final sensor = Dht(8, DHT22);
final lcd = LiquidCrystal(12, 11, 5, 4, 3, 2);
final heater = Led(pin: 13);

void showReading(double temperature) {
  lcd.setCursor(0, 0);
  lcd.print('Temp ');
  lcd.print(temperature, digits: 1);
  lcd.print('    ');
  lcd.setCursor(8, 1);
  if (thermostat.heating) {
    lcd.print('heating');
  } else {
    lcd.print('idle   ');
  }
}

void showSetpoint(int value) {
  lcd.setCursor(0, 1);
  lcd.print('Set ');
  lcd.print(value);
  lcd.print(' ');
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          OnStart(() {
            lcd.begin(16, 2);
            sensor.begin();
            final saved = EEPROM.read(setpointAddress);
            if (saved >= lowest && saved <= highest) setpoint.value = saved;
          }),
          heater,
          Button(
              pin: 6,
              onPressed: () {
                if (setpoint.value < highest) setpoint.value++;
              }),
          Button(
              pin: 7,
              onPressed: () {
                if (setpoint.value > lowest) setpoint.value--;
              }),
          Every(Duration(milliseconds: 2500), () {
            if (sensor.read()) {
              final temperature = sensor.readTemperature();
              thermostat.update(temperature, setpoint.value);
              heater.set(thermostat.heating);
              showReading(temperature);
            } else {
              heater.off();
              lcd.setCursor(0, 0);
              lcd.print('Temp error  ');
            }
          }),
          Watch(setpoint, (v) {
            EEPROM.update(setpointAddress, v);
            showSetpoint(v);
          }),
        ],
      ),
    );
