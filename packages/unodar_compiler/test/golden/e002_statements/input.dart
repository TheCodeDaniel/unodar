import 'package:unodar/unodar.dart';

int n = 0;

void setup() {}

void loop() {
  switch (n) {
    case 0:
      n = 1;
  }
  for (final i in [1, 2]) {
    n = i;
  }
  outer:
  while (n < 3) {
    n++;
  }
  try {
    n = 2;
  } finally {}
  throw 0;
  ;
  assert(n > 0);
  late int later;
  for (int i = 0, j = 0; i < j; i++) {}
  var (first, second) = (1, 2);
  n + 1;
}
