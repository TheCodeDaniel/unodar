import 'package:unodar/unodar.dart';

enum Mode { idle, heating }

Mode mode = Mode.heating;

void setup() {
  Serial.begin(9600);
  Serial.println(mode);
  Serial.println(mode.index);
}

void loop() {}
