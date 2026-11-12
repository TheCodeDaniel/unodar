@CppInclude('avr/wdt.h')
@CppInclude('avr/sleep.h')
library;

import 'package:unodar/unodar.dart';

int ticks = 0;

void kick() => cpp('wdt_reset();');

void setup() {
  cpp('wdt_enable(WDTO_2S);');
  pinMode(LED_BUILTIN, OUTPUT);
  // A raw string keeps backslashes; adjacent literals join; a multi-line literal keeps its lines.
  cpp(r'static const char path[] = "a\\b";');
  cpp('set_sleep_mode(SLEEP_MODE_IDLE);'
      ' sleep_enable();');
  cpp('''
if (MCUSR & _BV(WDRF)) {
  MCUSR = 0;
}''');
}

void loop() {
  ticks += 1;
  digitalWrite(LED_BUILTIN, ticks % 2 == 0 ? HIGH : LOW);
  cpp('sleep_cpu(); // renewed: only whole words count');
  kick();
  delay(500);
}
