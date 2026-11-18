import 'dart:async';

import 'package:unodar/unodar.dart';

// A first attempt by a Flutter developer who has not read the docs (Phase 7 newcomer corpus): a Timer. Only the
// import is reported, not each use of what it would have provided.
void setup() {
  Timer.periodic(Duration(seconds: 1), (_) {
    digitalWrite(LED_BUILTIN, HIGH);
  });
}

void loop() {}
