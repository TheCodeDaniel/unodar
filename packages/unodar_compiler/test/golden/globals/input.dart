/// Top-level variables: const -> constexpr, final -> const, mutable -> plain; inferred and sized types.
import 'package:unodar/unodar.dart';

const int ledPin = 13;
const blinkMs = 250; // Inferred int.
const int periodMs = blinkMs * 2 + 100;
final int startLevel = HIGH;
int counter = 0;
var ticks = -1;
const double ratio = 0.5;
double scale = 2; // An int literal in a double context is a double.
const bool enabled = true;
bool armed = !enabled;
const Uint8 brightness = Uint8(200);
Uint16 wide = Uint16(65535);
const Int16 offset = Int16(-300);
const int minInt = -2147483647 - 1;
const int hour = 60 * 60 * 1000;

void setup() {
  pinMode(ledPin, OUTPUT);
}

void loop() {
  counter = counter + 1;
  ticks += 1;
  scale = scale * ratio;
  armed = counter > periodMs;
  wide = Uint16(wide + brightness);
  digitalWrite(ledPin, startLevel);
  delay(blinkMs + offset + hour ~/ 1000 + minInt ~/ 1000000000);
}
