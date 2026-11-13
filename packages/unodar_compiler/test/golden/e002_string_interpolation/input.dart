import 'package:unodar/unodar.dart';

int count = 0;

void setup() {
  Serial.begin(9600);
}

void loop() {
  Serial.println('count = $count');
  Serial.print('next: ${count + 1}' ' items');
  Serial.print('a\x00b');
}
