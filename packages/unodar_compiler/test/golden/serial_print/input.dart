import 'package:unodar/unodar.dart';

const int baud = 9600;
int count = 0;
Uint8 small = Uint8(200);

void setup() {
  Serial.begin(baud);
  Serial.println('unodar ready');
  Serial.println('');
}

void loop() {
  count += 1;
  final level = analogRead(A0);
  final volts = level * 5.0 / 1023;
  final high = level > 512;

  Serial.print('count=');
  Serial.println(count);
  Serial.print('level: ');
  Serial.print(level);
  Serial.print(' = ');
  Serial.print(volts);
  Serial.println(' V');
  Serial.println(high);
  Serial.println(!high && count > 3);
  Serial.println(small);
  Serial.println(-count * 1000);
  Serial.println(1.5);
  // Escapes are re-encoded for C++; non-ASCII characters are sent as UTF-8.
  Serial.print('tab\there, "quotes", back\\slash, what??!, 25 °C\n');
  Serial.print(r'raw \n stays');
  Serial.println('adjacent ' 'literals');
  delay(1000);
}
