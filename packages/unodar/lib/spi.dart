/// SPI, the bus under most displays, SD cards and radios (Arduino's SPI library, part of the AVR core). Import it on
/// its own: `import 'package:unodar/spi.dart';`.
///
/// ```dart
/// SPI.begin();
/// SPI.beginTransaction(1000000, MSBFIRST, SPI_MODE0);
/// digitalWrite(10, LOW);            // select the chip
/// final reply = SPI.transfer(0x9F);
/// digitalWrite(10, HIGH);
/// SPI.endTransaction();
/// ```
///
/// See docs/SUBSET.md "SPI" for the pins it takes, the costs and what is verified in the simulator.
library;

export 'src/spi.dart';
