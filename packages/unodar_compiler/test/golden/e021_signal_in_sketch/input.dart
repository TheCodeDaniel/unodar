import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

void setup() {
  Serial.begin(9600);
}

void loop() {
  count.value++;
  Serial.println(count.value);
  final local = Signal(1);
}
