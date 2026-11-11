/// User functions: parameters, return values, `=>` bodies, calls in expressions, calls before declaration.
import 'package:unodar/unodar.dart';

const int ledPin = 13;

int squared(int x) => x * x;

double average(int a, int b) {
  return (a + b) / 2;
}

bool isEven(int n) => n % 2 == 0;

void blink(int pin, int ms) {
  digitalWrite(pin, HIGH);
  delay(ms);
  digitalWrite(pin, LOW);
  delay(ms);
}

void blinkTwice(int ms) => blink(ledPin, ms);

int clampMs(int ms) {
  if (ms < 0) {
    return 0;
  }
  return ms;
}

void earlyExit(bool skip) {
  if (skip) return;
  blink(ledPin, 10);
}

void setup() {
  pinMode(ledPin, OUTPUT);
}

void loop() {
  blinkTwice(clampMs(squared(10)));
  final double avg = average(3, 4);
  if (isEven(squared(3)) || avg > 3) {
    earlyExit(false);
  }
  blink(ledPin, squared(5));
  later();
}

void later() {}
