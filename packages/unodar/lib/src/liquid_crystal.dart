import 'interop.dart';

/// Arduino's `LiquidCrystal` (`LiquidCrystal.h`, LiquidCrystal 1.0.7) in 4-bit mode, R/W tied to GND.
///
/// Creating the object already initializes the display as one row (about 15 ms, before `setup()` runs); call
/// [begin] with the real size. Each character and command takes about 0.3 ms, [clear] and [home] 2.3 ms. There is no `println`:
/// a line break would show as two odd characters; use [setCursor].
@CppHeader('LiquidCrystal.h')
@CppClass('LiquidCrystal')
@CppPrint()
final class LiquidCrystal {
  /// The pins of the LCD's RS, E and D4–D7 lines.
  external LiquidCrystal(
      @CppPin() @CppType('uint8_t') int rs,
      @CppPin() @CppType('uint8_t') int enable,
      @CppPin() @CppType('uint8_t') int d4,
      @CppPin() @CppType('uint8_t') int d5,
      @CppPin() @CppType('uint8_t') int d6,
      @CppPin() @CppType('uint8_t') int d7);

  /// Initializes a display of [cols] columns (1 to 40) and [rows] rows (1 to 4), clears it and turns it on: about
  /// 10 ms.
  external void begin(@CppType('uint8_t') @CppRange(1, 40) int cols, @CppType('uint8_t') @CppRange(1, 4) int rows);

  /// Clears the display and moves the cursor to the top left: 2.3 ms.
  external void clear();

  /// Moves the cursor to the top left and undoes any scrolling: 2.3 ms.
  external void home();

  /// Moves the cursor to [col] (0 to 39) of [row] (0 to 3), counted from 0. Note the order: column first.
  external void setCursor(@CppType('uint8_t') @CppRange(0, 39) int col, @CppType('uint8_t') @CppRange(0, 3) int row);

  /// Writes the character with code [value] (0 to 255) at the cursor, e.g. 223 for a degree sign on most displays;
  /// returns 1.
  @CppType('size_t')
  external int write(@CppType('uint8_t') int value);

  /// Writes [value] as text at the cursor, like `Serial.print`. A string must be a literal. [digits] applies to a
  /// `double` only.
  external void print(Object value, {int digits = 2});

  /// Turns the display on (the text is kept while it is off).
  external void display();

  /// Turns the display off, keeping the text.
  external void noDisplay();

  /// Shows the cursor as an underline.
  external void cursor();

  /// Hides the underline cursor.
  external void noCursor();

  /// Makes the cursor position blink.
  external void blink();

  /// Stops the blinking.
  external void noBlink();

  /// Moves the whole text one position to the left.
  external void scrollDisplayLeft();

  /// Moves the whole text one position to the right.
  external void scrollDisplayRight();
}
