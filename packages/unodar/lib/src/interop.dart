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
