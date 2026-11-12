import 'package:unodar/unodar.dart';

int a = 60;
int b = 1000;
int c = -7;
int d = 2;
int e = 7;

bool selfTest() {
  if (a * b != 60000) {
    return false;
  }
  if (c % d != 1) {
    return false;
  }
  if (c ~/ d != -3) {
    return false;
  }
  if (e / d != 3.5) {
    return false;
  }
  if (a - b - c != -933) {
    return false;
  }
  if (a - (b - c) != -947) {
    return false;
  }
  if ((a > d ? 1 : 2) + 10 != 11) {
    return false;
  }
  int sum = 0;
  for (int i = 0; i < 10; i++) {
    if (i % 2 == 0) {
      continue;
    }
    if (i > 7) {
      break;
    }
    sum += i;
  }
  if (sum != 16) {
    return false;
  }
  return true;
}

void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  if (selfTest()) {
    digitalWrite(13, HIGH);
    delay(100);
    digitalWrite(13, LOW);
    delay(100);
  } else {
    digitalWrite(13, HIGH);
    delay(100);
  }
}
