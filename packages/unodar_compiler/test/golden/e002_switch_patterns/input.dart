import 'package:unodar/unodar.dart';

// Switch forms outside the subset (E002): patterns other than constants (relational, wildcard, variable), `when`
// guards, two cases with the same value (C++ rejects duplicate labels), labeled cases, a switch on a double, and
// switch expressions. (A `default` before other cases is already a Dart error, E007.)
const int one = 1;
bool flag = false;
double level = 0.5;

void setup() {}

void loop() {
  final n = millis();
  switch (n) {
    case > 5:
      flag = true;
    case 2 when flag:
      flag = false;
    case _:
      flag = true;
  }
  switch (n) {
    case 1:
      flag = true;
    case 2 || one:
      flag = false;
  }
  switch (n) {
    again:
    case 3:
      flag = true;
  }
  switch (level) {
    case 0.5:
      flag = true;
  }
  final code = switch (n) { 1 => 10, _ => 20 };
  delay(code);
}
