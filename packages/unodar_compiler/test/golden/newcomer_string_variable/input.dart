import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): a String variable.
// One diagnostic, at the type: the string literal it holds is not reported separately.
String greeting = 'Hello from the Uno';

void setup() {
  Serial.begin(9600);
}

void loop() {}
