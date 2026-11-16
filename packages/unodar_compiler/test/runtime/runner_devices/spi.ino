// Runner check (Phase 6 step 12): the scripted SPI slave of the avr8js runner. Hand-written C++ with the core's SPI
// library: three bytes in mode 1, MSB first, at 1 MHz (divider 16), then one in mode 3, LSB first, at 4 MHz
// (divider 4). Prints what the slave answered.
#include <Arduino.h>
#include <SPI.h>

void setup() {
  Serial.begin(9600);
  SPI.begin();
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE1));
  const uint8_t command[] = {0x9F, 0x00, 0x00};
  for (uint8_t b : command) {
    Serial.print(SPI.transfer(b), HEX);
    Serial.print(' ');
  }
  SPI.endTransaction();
  Serial.println();
  SPI.beginTransaction(SPISettings(4000000, LSBFIRST, SPI_MODE3));
  Serial.println(SPI.transfer(0x55), HEX);
  SPI.endTransaction();
  Serial.println("DONE");
}

void loop() {}
