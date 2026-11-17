import 'package:unodar/unodar.dart';

// Enums (Phase 6 step 7): a simple enum as the type of a signal, a field, a `const`, a local, a parameter and a
// return value; `==`, `!=`, `?:` and `.index` (widened to 32 bits in `* 20000`). Also an avr8js behaviour program:
// each tick feeds a temperature to the thermostat, which switches mode; a Watch reports each new mode.
enum Mode { idle, heating, cooling }

const Mode start = Mode.cooling;

final mode = Signal(Mode.idle);

Mode modeFor(int temperature) {
  if (temperature < 18) return Mode.heating;
  return temperature > 24 ? Mode.cooling : Mode.idle;
}

class Thermostat {
  int changes = 0;
  Mode previous = start;

  void update(int temperature) {
    final Mode next = modeFor(temperature);
    if (next != mode.value) {
      mode.value = next;
      changes++;
    }
  }

  bool get active => mode.value != Mode.idle;
}

final thermostat = Thermostat();
int readings = 0;

int temperatureAt(int n) => n == 1 ? 10 : 30;

void main() => runDevice(Device(board: Uno(), children: [
      Every(Duration(milliseconds: 500), () {
        readings++;
        thermostat.update(temperatureAt(readings));
        Serial.print(mode.value.index);
        Serial.print(' ');
        Serial.print(thermostat.changes);
        Serial.print(' ');
        Serial.print(thermostat.active);
        Serial.print(' ');
        Serial.print(mode.value.index * 20000);
        Serial.print(' ');
        Serial.println(thermostat.previous == mode.value);
        thermostat.previous = mode.value;
      }),
      Watch(mode, (m) {
        Serial.print('mode ');
        Serial.println(m.index);
      }),
    ]));
