import 'package:unodar/spi.dart';
import 'package:unodar/unodar.dart';

void setup() {
  SPI.begin();
  SPI.beginTransaction(1000000, 2, SPI_MODE0);
  SPI.beginTransaction(1000000, MSBFIRST, 4);
  SPI.beginTransaction(-1, MSBFIRST, SPI_MODE1);
  SPI.transfer(256);
  SPI.transfer16(65536);
}

void loop() {}
