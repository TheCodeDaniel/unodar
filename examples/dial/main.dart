// Dial: a potentiometer on A0 turns a servo on pin 9, the LED lights up past the halfway mark, and the reading is
// reported over Serial twice a second. Uses the Phase 3 hardware API: analogRead, millis, Serial with strings and
// `digits:`, the Servo binding with a named argument, and a watchdog through the C++ escape hatch.
//
// Wiring: potentiometer wiper to A0 (ends to 5V and GND), servo signal to pin 9. Needs the Servo library:
//          arduino-cli lib install Servo@1.3.0
// Build:   dart run packages/unodar_compiler/bin/unodar.dart build examples/dial/main.dart -o out
@CppInclude('avr/wdt.h')
library;

import 'package:unodar/unodar.dart';

const int potPin = A0;
const int reportEvery = 500; // ms
final servo = Servo();
int lastReport = 0;

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  servo.attach(9, min: 600, max: 2400);
  cpp('wdt_enable(WDTO_1S);');
  Serial.println('dial ready');
}

void loop() {
  cpp('wdt_reset();');
  final level = analogRead(potPin);
  final angle = level * 180 ~/ 1023;
  servo.write(angle);
  digitalWrite(LED_BUILTIN, level > 511 ? HIGH : LOW);

  // Works across the millis() wrap: the subtraction wraps like Arduino's unsigned long idiom.
  final now = millis();
  if (now - lastReport >= reportEvery) {
    lastReport = now;
    Serial.print('level=');
    Serial.print(level);
    Serial.print(' angle=');
    Serial.print(angle);
    Serial.print(' volts=');
    Serial.println(level * 5.0 / 1023, digits: 3);
  }
  delay(15);
}
