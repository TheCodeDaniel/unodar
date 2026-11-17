// The library's names are spelled like the C++ ones: SPI, MSBFIRST, SPI_MODE0.
// ignore_for_file: non_constant_identifier_names, constant_identifier_names
import 'interop.dart';

/// Arduino's SPI master (`SPI.h`, in the AVR core), through unodar's shim `unodar_spi.h`, which takes the settings
/// of a transaction as three numbers instead of an `SPISettings` object. There is one, [SPI]; it cannot be created.
///
/// SPI uses pins 11 (MOSI), 12 (MISO) and 13 (SCK, also the built-in LED), and [begin] makes pin 10 (SS) an output.
@CppHeader('unodar_spi.h')
@CppClass('unodar::Spi')
abstract final class SpiClass {
  /// Starts SPI as master: SCK, MOSI and SS become outputs, SS high.
  external void begin();

  /// Stops SPI (after as many calls as [begin] had).
  external void end();

  /// Sends [value] (0 to 255) and returns the byte received at the same time.
  @CppType('uint8_t')
  external int transfer(@CppType('uint8_t') int value);

  /// Sends [value] (0 to 65535) as two bytes, in the transaction's bit order, and returns the two bytes received.
  @CppType('uint16_t')
  external int transfer16(@CppType('uint16_t') int value);

  /// Sets the bus for one device: [clock] in Hz (the fastest speed not above it, from 8 MHz down to 125 kHz),
  /// [bitOrder] [MSBFIRST] or [LSBFIRST], [mode] 0 to 3 ([SPI_MODE0]–[SPI_MODE3]). Interrupts that use SPI wait
  /// until [endTransaction].
  external void beginTransaction(@CppType('uint32_t') int clock, @CppType('uint8_t') @CppRange(0, 1) int bitOrder,
      @CppType('uint8_t') @CppRange(0, 3) int mode);

  /// Ends the transaction [beginTransaction] started.
  external void endTransaction();
}

/// The SPI bus (C++ `unodar_spi`, which forwards to Arduino's `SPI`).
@CppName('unodar_spi')
external final SpiClass SPI;

/// Most significant bit first (C++ `MSBFIRST`).
@CppName('MSBFIRST')
const int MSBFIRST = 1;

/// Least significant bit first (C++ `LSBFIRST`).
@CppName('LSBFIRST')
const int LSBFIRST = 0;

/// SPI mode 0: clock idle low, data sampled on the rising edge.
const int SPI_MODE0 = 0;

/// SPI mode 1: clock idle low, data sampled on the falling edge.
const int SPI_MODE1 = 1;

/// SPI mode 2: clock idle high, data sampled on the falling edge.
const int SPI_MODE2 = 2;

/// SPI mode 3: clock idle high, data sampled on the rising edge.
const int SPI_MODE3 = 3;
