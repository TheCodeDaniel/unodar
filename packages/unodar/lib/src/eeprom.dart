// The library's object is spelled like the C++ one, EEPROM.
// ignore_for_file: non_constant_identifier_names
import 'interop.dart';

/// Arduino's `EEPROMClass` (`EEPROM.h`, in the AVR core). There is one, [EEPROM]; it cannot be created.
///
/// Addresses are 0 to 1023 on the Uno; constant addresses outside are rejected (E004). A non-constant address
/// outside wraps around (the hardware uses its low 10 bits), and a value is stored as a byte (0 to 255).
@CppHeader('EEPROM.h')
@CppClass('EEPROMClass')
abstract final class EepromClass {
  /// The byte at [address], 0 to 255 (255 in an erased cell).
  @CppType('uint8_t')
  external int read(@CppType('int') @CppRange(0, 1023) int address);

  /// Writes [value] at [address], always: about 3.3 ms, and each cell lasts about 100,000 writes. Prefer [update].
  external void write(@CppType('int') @CppRange(0, 1023) int address, @CppType('uint8_t') int value);

  /// Writes [value] at [address] only if the byte there differs, which saves time and wear.
  external void update(@CppType('int') @CppRange(0, 1023) int address, @CppType('uint8_t') int value);

  /// The number of bytes: 1024 on the Uno.
  @CppType('uint16_t')
  external int length();
}

/// The EEPROM (C++ `EEPROM`).
external final EepromClass EEPROM;
