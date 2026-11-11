/// Storing an int in a sized type without the explicit constructor is a Dart type error.
import 'package:unodar/unodar.dart';

Uint8 level = 300;

void setup() {}

void loop() {
  Uint8 x = Uint8(1);
  x++;
  x += 1;
}
