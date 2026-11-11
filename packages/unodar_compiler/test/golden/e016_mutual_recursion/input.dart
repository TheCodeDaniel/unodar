import 'package:unodar/unodar.dart';

void ping(int n) {
  if (n > 0) pong(n - 1);
}

void pong(int n) {
  if (n > 0) ping(n - 1);
}

void a() => b();

void b() => c();

void c() {
  a();
}

void setup() {}

void loop() {}
