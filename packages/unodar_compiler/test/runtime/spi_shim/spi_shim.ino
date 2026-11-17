// The SPI shim runtime/unodar_spi.h on its own (Phase 6 step 14), hand-written. For each mode 0..3 and both bit
// orders, a transaction through the shim sends one byte; the runner logs the SPCR settings of each byte, which must
// equal those of SPISettings with Arduino's SPI_MODEn. Ends with transfer16 and end().
#include <Arduino.h>
#include "unodar_spi.h"

void setup() {
  Serial.begin(9600);
  unodar_spi.begin();
  for (uint8_t mode = 0; mode < 4; mode++) {
    unodar_spi.beginTransaction(2000000, MSBFIRST, mode);
    unodar_spi.transfer(0x10 + mode);
    unodar_spi.endTransaction();
  }
  // A clock that is not a compile-time constant takes SPISettings' loop instead of its if-cascade.
  volatile uint32_t slow = 100000;
  unodar_spi.beginTransaction(slow, LSBFIRST, 2);
  unodar_spi.transfer(0x20);
  unodar_spi.endTransaction();
  unodar_spi.beginTransaction(8000000, MSBFIRST, 0);
  Serial.println(unodar_spi.transfer16(0x1234), HEX);
  unodar_spi.endTransaction();
  unodar_spi.end();
  Serial.println(SPCR & _BV(SPE) ? "on" : "off");
  Serial.println("DONE");
}

void loop() {}
