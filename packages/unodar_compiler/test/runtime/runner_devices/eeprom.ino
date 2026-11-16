// Runner check (Phase 6 step 12): the avr8js EEPROM model, file-backed across runs, counting byte writes. Hand-written
// C++ with avr-libc's EEPROM functions (not unodar's wrapper). Byte 0 counts boots (erased EEPROM reads 0xFF); byte 1
// is updated twice to the same value, which avr-libc's eeprom_update_byte writes only once.
#include <Arduino.h>
#include <avr/eeprom.h>

void setup() {
  Serial.begin(9600);
  uint8_t boots = eeprom_read_byte((uint8_t *)0);
  if (boots == 0xFF) boots = 0;
  Serial.print("boot ");
  Serial.println(boots);
  eeprom_write_byte((uint8_t *)0, boots + 1);
  eeprom_update_byte((uint8_t *)1, 0x42);
  eeprom_update_byte((uint8_t *)1, 0x42);
  Serial.print("byte1 ");
  Serial.println(eeprom_read_byte((uint8_t *)1), HEX);
  Serial.println("DONE");
}

void loop() {}
