/// Interop with C++: annotations that describe existing C++ classes, and the raw C++ escape hatch.
///
/// The compiler reads these annotations; at C++ level a binding is a direct call, with no wrapper and no runtime.
/// See docs/SUBSET.md "Binding C++ classes" and "Escape hatch".
library;

/// The header that declares a bound C++ class, e.g. `@CppHeader('Servo.h')`. Emitted as `#include <Servo.h>` when
/// the program uses the class.
final class CppHeader {
  const CppHeader(this.header);

  final String header;
}

/// Marks a class as a binding to the C++ class [name] (`ns::Name` allowed). Its members must be `external`.
final class CppClass {
  const CppClass(this.name);

  final String name;
}

/// The C++ name of a binding method or an external object, when it differs from the Dart name. Use it for C++
/// overloads: give each overload its own Dart name and map them to one C++ name.
final class CppName {
  const CppName(this.name);

  final String name;
}

/// The exact C++ type of a binding parameter, or (on a method) of its result, e.g. `@CppType('uint8_t')`.
///
/// Constant arguments are range-checked against it, other arguments are converted to it explicitly, and integer
/// results keep 32-bit `int` arithmetic. Accepted: `bool`, `float`, `double`, `int8_t`, `uint8_t`, `int16_t`,
/// `uint16_t`, `int32_t`, `uint32_t`, `int`, `unsigned int`, `long`, `unsigned long`, `size_t`.
final class CppType {
  const CppType(this.type);

  final String type;
}

/// Narrows the values a binding's integer parameter accepts to [min]..[max], within its C++ type, e.g.
/// `@CppRange(33, 1059)`. Constant arguments outside are rejected (E004); the C++ type and conversion stay those of
/// `@CppType`. Use it where the library only handles part of the type's range.
final class CppRange {
  const CppRange(this.min, this.max);

  final int min;
  final int max;
}

/// Marks an integer parameter of a binding constructor as an Arduino pin, e.g.
/// `external LiquidCrystal(@CppPin() @CppType('uint8_t') int rs, …);`. A constant pin is checked like a widget's: 0 to
/// 19 (E004), and used by no widget and no other bound object (E022). A `@CppRange` narrows it further, e.g.
/// `@CppPin() @CppRange(2, 19)` where pins 0 and 1 (Serial's) cannot work.
final class CppPin {
  const CppPin();
}

/// The pins an `external final` object takes whenever the program uses it, each with its role, e.g.
/// `@CppUsesPins({10: 'SS', 11: 'MOSI', 12: 'MISO', 13: 'SCK'})` on `SPI`. In a program that uses the object, no
/// widget and no `@CppPin` of a bound object may use one of them (E022).
final class CppUsesPins {
  const CppUsesPins(this.pins);

  final Map<int, String> pins;
}

/// Gives the `print` and `println` of a binding class the dispatch `Serial` has, for a C++ class derived from
/// Arduino's `Print` (LiquidCrystal, SoftwareSerial): a string literal is a flash string, a `bool` prints
/// `true`/`false`, and a `double` takes `digits`. Declare them as
/// `external void print(Object value, {int digits = 2});` and the same for `println`.
final class CppPrint {
  const CppPrint();
}

/// An extra header for raw C++, e.g. `@CppInclude('avr/wdt.h') library;`. Allowed only on the `library;` directive.
final class CppInclude {
  const CppInclude(this.header);

  final String header;
}

/// Emits [code] verbatim as C++ (the escape hatch).
///
/// Only as a statement of its own, with a single string literal: `cpp('wdt_reset();');`. Unodar does not check
/// the C++, except that it rejects heap use (`new`, `malloc`, `String`, …).
external void cpp(String code);
