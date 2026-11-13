import 'package:unodar/unodar.dart';

void setup() {}

void loop() {
  cpp('char *buffer = (char *) malloc(16);');
  cpp('int *p = new int[4]; delete[] p;');
  cpp('String s = "x";');
  cpp('free(0); // freeze is fine: matched by whole word only');
  cpp('static char freezer[4]; // no heap word here');
}
