import 'package:unodar/unodar.dart';

int mode = 0;

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  if (mode == 0) {
    digitalWrite(13, HIGH);
  }
  if (mode == 1) {
    digitalWrite(13, LOW);
  } else {
    digitalWrite(13, HIGH);
  }
  if (mode < 0) {
    mode = 0;
  } else if (mode > 3) {
    mode = 3;
  } else if (mode == 2) {
    mode += 1;
  } else {
    mode -= 1;
  }
  if (mode == 3) delay(100);
  if (mode != 3)
    delay(50);
  else
    delay(25);
}
