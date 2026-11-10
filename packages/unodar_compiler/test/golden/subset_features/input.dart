/// Exercises every Phase 1 construct listed in docs/SUBSET.md that the blink case does not.
library;

// `show`/`hide` combinators are allowed on the unodar import.
import 'package:unodar/unodar.dart' show pinMode, digitalWrite, delay, HIGH, LOW, OUTPUT, INPUT, INPUT_PULLUP;

/// Doc comments and comments anywhere are ignored.
void loop() {} // Order does not matter, and an empty body is fine.

void setup() {
  pinMode(0x0D, OUTPUT); // Hex literals are emitted as decimal.
  pinMode(2, INPUT);
  pinMode(3, INPUT_PULLUP);
  digitalWrite(13, HIGH);
  digitalWrite(13, LOW);
  delay(0);
}
