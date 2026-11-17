/// Character LCDs with an HD44780 controller (16×2, 20×4, …) wired in parallel, 4-bit mode (Arduino's LiquidCrystal
/// library 1.0.7, from the library index). Import it on its own: `import 'package:unodar/liquid_crystal.dart';`.
///
/// ```dart
/// final lcd = LiquidCrystal(12, 11, 5, 4, 3, 2);   // RS, E, D4, D5, D6, D7
/// lcd.begin(16, 2);
/// lcd.print('Temp ');
/// lcd.print(21.5, digits: 1);
/// lcd.setCursor(0, 1);                             // column 0, row 1
/// ```
///
/// Not LCDs with an I²C backpack (a PCF8574 board): those need another library. See docs/SUBSET.md "LiquidCrystal"
/// for the waits, the costs and what is verified in the simulator.
library;

export 'src/liquid_crystal.dart';
