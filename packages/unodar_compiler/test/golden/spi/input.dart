import 'package:unodar/spi.dart';
import 'package:unodar/unodar.dart';

// The SPI wrapper (Phase 6 step 14), imported on its own. Reads a JEDEC ID (command 0x9F) from a flash chip selected
// by pin 10, the way most SPI devices are talked to, then sends one byte in mode 3, LSB first. Also an avr8js
// behaviour program, against the runner's scripted SPI slave.
const int chipSelect = 10;

int readId() {
  SPI.beginTransaction(4000000, MSBFIRST, SPI_MODE0);
  digitalWrite(chipSelect, LOW);
  SPI.transfer(0x9F);
  final maker = SPI.transfer(0);
  final type = SPI.transfer16(0);
  digitalWrite(chipSelect, HIGH);
  SPI.endTransaction();
  return maker * 65536 + type;
}

void setup() {
  Serial.begin(9600);
  pinMode(chipSelect, OUTPUT);
  digitalWrite(chipSelect, HIGH);
  SPI.begin();
  Serial.println(readId());
  SPI.beginTransaction(1000000, LSBFIRST, SPI_MODE3);
  SPI.transfer(0xA5);
  SPI.endTransaction();
  SPI.end();
  Serial.println('DONE');
}

void loop() {}
