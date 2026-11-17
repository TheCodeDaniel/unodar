import 'package:unodar/software_serial.dart';
import 'package:unodar/unodar.dart';

// The SoftwareSerial wrapper (Phase 6 step 16), imported on its own. `gps` receives on pin 10 and sends on 11; a
// Radio owns a second port as a member object (RX 8, TX 9). Also an avr8js behaviour program: the TX pins are
// decoded from the pin log, and 70 bytes scheduled on pin 10 arrive while setup() waits, overflowing the buffer.
final class Radio {
  final SoftwareSerial link = SoftwareSerial(8, 9);
  int sent = 0;

  void hello() {
    link.println('radio');
    sent++;
  }
}

final gps = SoftwareSerial(10, 11);
final radio = Radio();

void setup() {
  Serial.begin(9600);
  radio.link.begin(9600);
  gps.begin(9600);
  gps.print('gps ');
  gps.println(gps.isListening());
  radio.hello();
  gps.write(65);
  delay(150);
  Serial.print('overflow ');
  Serial.println(gps.overflow());
  int kept = 0;
  int last = -1;
  while (gps.available() > 0) {
    last = gps.read();
    kept++;
  }
  Serial.print('kept ');
  Serial.println(kept);
  Serial.print('last ');
  Serial.println(last);
  Serial.print('empty ');
  Serial.println(gps.read());
  Serial.println('DONE');
}

void loop() {}
