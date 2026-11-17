import 'package:unodar/unodar.dart';

// `switch` statements (Phase 6 step 18) on an enum and on ints, with constant cases. Dart 3 cases never fall through:
// a non-empty case ends with a C++ `break`, and an empty case shares the body of the next one, like `||`. Also an
// avr8js behaviour program: it prints what each switch chose.
enum Mode { idle, heating, cooling, error }

const int limit = 3;

int score(Mode mode) {
  switch (mode) {
    case Mode.idle:
      return 0;
    case Mode.heating || Mode.cooling:
      return 10;
    case Mode.error:
      return -1;
  }
}

int classify(int value) {
  var result = 0;
  switch (value) {
    case -1:
      result = 100;
    case 0:
    case 1:
      result = 200;
      result += value;
    case limit:
      final doubled = value * 2;
      result = doubled;
    case 4 || 5:
    default:
      result = 999;
  }
  return result;
}

void count(int n) {
  var total = 0;
  for (var i = 0; i < n; i++) {
    switch (i) {
      case 2:
        continue;
      case 4:
        break;
    }
    total += i;
  }
  Serial.println(total);
}

void setup() {
  Serial.begin(9600);
  Serial.println(score(Mode.idle));
  Serial.println(score(Mode.heating));
  Serial.println(score(Mode.cooling));
  Serial.println(score(Mode.error));
  for (var v = -2; v <= 6; v++) {
    Serial.println(classify(v));
  }
  count(6);
  Serial.println('DONE');
}

void loop() {}
