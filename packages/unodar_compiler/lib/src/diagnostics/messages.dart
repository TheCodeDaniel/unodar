import 'codes.dart';
import 'diagnostic.dart';

/// Factories for every diagnostic. All user-facing wording lives here; `docs/DIAGNOSTICS.md` shows each one, and
/// `docs_test.dart` compiles the documented examples to keep the two identical.
///
/// Message style: lower-case start, states what is wrong in the user's terms. Suggestion style: an imperative
/// sentence saying what to do instead.
abstract final class Diagnostics {
  static const _supportedTypes = 'int, double, bool, Uint8, Uint16, and Int16';

  static Diagnostic missingEntryPoint(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.missingEntryPoint,
        location: at,
        message: "missing required function '$name()'. Every unodar sketch needs both setup() and loop().",
        suggestion: 'Add `void $name() { }` at the top level of this file.',
      );

  /// [what] names the construct ("a do-while loop"); [suggestion] is specific to it.
  static Diagnostic unsupportedStatement(String what, String suggestion, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedStatement,
        location: at,
        message: '$what is not supported in this version.',
        suggestion: suggestion,
      );

  /// [cppExample] is the call as C++ text for the escape-hatch hint (`tone(8, 440)`), or null for a method call on
  /// a Dart value, which has no C++ equivalent.
  static Diagnostic unknownFunction(String name, String? cppExample, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unknownFunction,
        location: at,
        message: "unknown function '$name': it is neither declared in this file nor part of the unodar API.",
        suggestion: cppExample == null
            ? 'Methods of numbers and other Dart values are not supported; use operators or a function declared in '
                'this file. See docs/SUBSET.md for the unodar API.'
            : 'Declare the function in this file, or call the Arduino function through the escape hatch, e.g. '
                "`cpp('$cppExample;');`. See docs/SUBSET.md for the unodar API.",
      );

  static Diagnostic argumentOutOfRange(
    String value,
    String parameter,
    String function,
    String cppType,
    String range,
    SourceLocation at,
  ) =>
      Diagnostic(
        code: DiagnosticCode.unsupportedArgument,
        location: at,
        message: "argument $value is out of range for parameter '$parameter' of $function, which is "
            '${_article(cppType)} $cppType ($range).',
        suggestion: 'Pass a value from $range.',
      );

  static Diagnostic argumentOutsideCppRange(
          String value, String parameter, String function, String range, SourceLocation at) =>
      Diagnostic(
        code: DiagnosticCode.unsupportedArgument,
        location: at,
        message: "argument $value is out of range for parameter '$parameter' of $function, which accepts $range "
            '(`@CppRange`).',
        suggestion: 'Pass a value from $range; the library does not handle values outside it.',
      );

  static Diagnostic namedArgument(String name, String function, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedArgument,
        location: at,
        message: "$function has no named parameter '$name'.",
        suggestion: 'Pass the arguments positionally, in the order of the declaration.',
      );

  static Diagnostic digitsWithoutDouble(String type, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedArgument,
        location: at,
        message: "'digits' only applies when printing a double, but this value is ${_article(type)} $type.",
        suggestion: "Remove `digits:`. For an int, Arduino's second argument would be the number base, not decimals.",
      );

  static Diagnostic unsupportedDeclaration(String what, SourceLocation at, {String? suggestion}) => Diagnostic(
        code: DiagnosticCode.unsupportedDeclaration,
        location: at,
        message: '$what is not supported in this version. Only top-level functions, variables, and binding classes '
            'may be declared.',
        suggestion:
            suggestion ?? 'Remove this declaration; see docs/SUBSET.md for what may be declared at the top level.',
      );

  static Diagnostic invalidEntrySignature(String name, String problem, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.invalidEntrySignature,
        location: at,
        message: "invalid signature for '$name': $problem.",
        suggestion: 'Declare it exactly as `void $name() { ... }`: return type void, no parameters, a block body.',
      );

  static Diagnostic analysisError(String analyzerMessage, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.analysisError,
        location: at,
        message: 'Dart analysis error: $analyzerMessage',
        suggestion: 'Fix the Dart error first; `dart analyze` on this file shows the same problem.',
      );

  static Diagnostic unsupportedMain(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedMain,
        location: at,
        message: 'unsupported main(): it may only contain a single `runDevice(Device(…))` call.',
        suggestion: 'Describe the device with widgets, e.g. '
            '`void main() => runDevice(Device(board: Uno(), children: [Led(pin: 13)]));`, or write `setup()` and '
            '`loop()` instead.',
      );

  static Diagnostic nullableType(String type, String nonNullable, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedType,
        location: at,
        message: "the nullable type '$type' is not supported in this version.",
        suggestion: "Use the non-nullable type '$nonNullable' and give the variable a value.",
      );

  static Diagnostic unsupportedType(String type, SourceLocation at, {bool isConditional = false}) => Diagnostic(
        code: DiagnosticCode.unsupportedType,
        location: at,
        message: "the type '$type' is not supported in this version. Only $_supportedTypes are supported.",
        suggestion: isConditional
            ? 'Make both branches the same type, e.g. write `1.0` instead of `1`.'
            : 'Use one of the supported types; see docs/SUBSET.md.',
      );

  static Diagnostic boolNumberComparison(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedType,
        location: at,
        message: 'comparing a bool with a number is not supported: Dart says they are never equal, but C++ '
            'converts the bool to 0 or 1.',
        suggestion: 'Compare numbers with numbers and bools with bools.',
      );

  static Diagnostic integerLiteralOutOfRange(String literal, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.constantOutOfRange,
        location: at,
        message: 'the integer literal $literal is outside the 32-bit int range (-2147483648 to 2147483647).',
        suggestion: 'unodar ints are 32-bit (int32_t). For the minimum value write `-2147483647 - 1`.',
      );

  static Diagnostic constantOverflow(int value, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.constantOutOfRange,
        location: at,
        message: 'this constant expression computes $value, which is outside the 32-bit int range '
            '(-2147483648 to 2147483647).',
        suggestion: 'unodar ints are 32-bit (int32_t). Use smaller values; see "Known deviations from Dart" in '
            'docs/SUBSET.md.',
      );

  static Diagnostic doubleLiteralOutOfRange(String literal, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.constantOutOfRange,
        location: at,
        message: 'the double literal $literal is outside the float range (about -3.4e38 to 3.4e38).',
        suggestion: 'unodar doubles are 32-bit floats; see "Known deviations from Dart" in docs/SUBSET.md.',
      );

  static Diagnostic constantDivisionByZero(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.constantOutOfRange,
        location: at,
        message: 'this constant expression divides by zero.',
        suggestion: 'Use a divisor that is not zero.',
      );

  static Diagnostic unsupportedSignature(String name, String problems, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedSignature,
        location: at,
        message: "unsupported signature for function '$name': $problems.",
        suggestion: 'Use only required positional parameters with a supported type, e.g. '
            '`int add(int a, int b) { ... }`.',
      );

  static Diagnostic closure(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.functionValue,
        location: at,
        message: 'a closure is not supported in this version. Functions can only be declared at the top level.',
        suggestion: 'Declare a top-level function and call it directly.',
      );

  static Diagnostic functionReference(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.functionValue,
        location: at,
        message: "a function reference ('$name') is not supported in this version. Functions can only be called "
            'directly.',
        suggestion: 'Call the function instead, e.g. `$name()`.',
      );

  static Diagnostic callbackReference(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.functionValue,
        location: at,
        message: "a function reference ('$name') cannot be a widget callback.",
        suggestion: 'Write a closure that calls it: `() { $name(); }`.',
      );

  /// [problem] is `it is async`, `it is a generator`.
  static Diagnostic callbackShape(String problem, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.functionValue,
        location: at,
        message: 'unsupported widget callback: $problem.',
        suggestion: 'Write a plain closure without parameters, `() { … }`; it runs to the end inside loop().',
      );

  static Diagnostic localFunction(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.functionValue,
        location: at,
        message: "a local function ('$name') is not supported in this version. Functions can only be declared at "
            'the top level.',
        suggestion: 'Move it to the top level of the file.',
      );

  static Diagnostic callNextToGlobal(String call, String global, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.evaluationOrder,
        location: at,
        message: "'$call' may run before or after '$global' is read in the generated C++, but Dart always evaluates "
            'left to right.',
        suggestion: "Store the call's result in a local variable first, e.g. `final value = $call;`.",
      );

  static Diagnostic twoCalls(String first, String second, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.evaluationOrder,
        location: at,
        message: "'$first' and '$second' may run in either order in the generated C++, but Dart always evaluates "
            'left to right.',
        suggestion: "Store one call's result in a local variable first, e.g. `final value = $first;`.",
      );

  /// [reason] completes "'name' cannot be used as a name: …"; [rename] is a suggested new name, if any.
  static Diagnostic reservedName(String name, String reason, String? rename, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.reservedName,
        location: at,
        message: "'$name' cannot be used as a name: $reason.",
        suggestion: rename == null ? 'Rename it.' : 'Rename it, e.g. `$rename`.',
      );

  static Diagnostic nonConstantInitializer(String variable, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.nonConstantInitializer,
        location: at,
        message: "the initializer of top-level variable '$variable' is not a compile-time constant.",
        suggestion: 'Use only literals, unodar constants, and `const` variables declared above it; assign other '
            'values in setup().',
      );

  static Diagnostic forwardReference(String variable, String later, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.nonConstantInitializer,
        location: at,
        message: "the initializer of top-level variable '$variable' refers to '$later', which is declared later.",
        suggestion: "Move the declaration of '$later' above '$variable'.",
      );

  static Diagnostic recursion(String function, List<String> path, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.recursion,
        location: at,
        message: "recursion is not supported: '$function' calls itself through ${path.join(' → ')}.",
        suggestion: "Rewrite it with a loop. The Uno's 2 KB stack has no overflow check, so recursion is rejected.",
      );

  // ---------------------------------------------------------------------------------------------------------------
  // E017: binding classes and interop annotations.

  /// [kind] is e.g. `a field`, `a getter`; [help] says what to do with that kind of member.
  static Diagnostic bindingMember(String kind, String name, String help, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.invalidBinding,
        location: at,
        message: "a binding class cannot have $kind ('$name'). Only an external constructor and external methods are "
            'allowed.',
        suggestion: help,
      );

  /// [kind] is `method` or `constructor`; [problems] completes "it has …".
  static Diagnostic bindingSignature(String kind, String name, String problems, String help, SourceLocation at) =>
      Diagnostic(
        code: DiagnosticCode.invalidBinding,
        location: at,
        message: "unsupported binding $kind '$name': it has $problems.",
        suggestion: help,
      );

  static Diagnostic bindingClass(String name, String problems, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.invalidBinding,
        location: at,
        message: "unsupported binding class '$name': $problems.",
        suggestion: 'A binding describes one existing C++ class as it is: no extends, implements, with, or type '
            'parameters, and an external constructor unless the class is abstract. See "Binding C++ classes" in '
            'docs/SUBSET.md.',
      );

  static Diagnostic misplacedAnnotation(String annotation, String allowed, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.invalidBinding,
        location: at,
        message: '@$annotation is not allowed here: it applies only to $allowed.',
        suggestion: 'Remove it, or move it to $allowed.',
      );

  static Diagnostic annotationArgument(String annotation, String problem, String help, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.invalidBinding,
        location: at,
        message: 'invalid @$annotation: $problem.',
        suggestion: help,
      );

  // ---------------------------------------------------------------------------------------------------------------
  // E018: bound objects.

  static Diagnostic boundObjectNotFinal(String name, String example, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.boundObjectMisuse,
        location: at,
        message: "the bound object '$name' must be declared `final`.",
        suggestion: 'Write `$example`. C++ objects are created once, as global variables.',
      );

  static Diagnostic boundObjectInitializer(String name, String cls, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.boundObjectMisuse,
        location: at,
        message: "the bound object '$name' must be initialized by calling the $cls constructor.",
        suggestion: 'Write `final $name = $cls(…);` with constant arguments.',
      );

  static Diagnostic abstractBoundObject(String name, String cls, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.boundObjectMisuse,
        location: at,
        message: "the bound object '$name' cannot be created: $cls is abstract and is only reached through existing "
            'C++ objects.',
        suggestion: "Call the existing object's methods directly, or name it with `external final $cls $name;`.",
      );

  /// [position] is `a local variable`, `a parameter`, or `a return value`.
  static Diagnostic bindingTypePosition(String position, String type, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.boundObjectMisuse,
        location: at,
        message: "$position of the binding type '$type' is not supported. Bound objects can only be top-level "
            '`final` variables.',
        suggestion: 'Use the top-level object directly instead of passing it around.',
      );

  static Diagnostic boundObjectUse(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.boundObjectMisuse,
        location: at,
        message: "the bound object '$name' can only be used to call its methods.",
        suggestion: 'Call a method on it, e.g. `$name.begin();`; it cannot be stored, compared, or passed.',
      );

  static Diagnostic bindingConstructorPosition(String cls, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.boundObjectMisuse,
        location: at,
        message: 'a $cls object can only be created as the initializer of a top-level `final` variable.',
        suggestion: 'Declare it at the top level, e.g. `final ${lowerFirst(cls)} = $cls(…);`, and use that.',
      );

  // ---------------------------------------------------------------------------------------------------------------
  // E019, E020: the escape hatch.

  static Diagnostic cppArgument(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.cppMisuse,
        location: at,
        message: 'the argument of cpp() must be a string literal without interpolation.',
        suggestion: "Write the C++ text out in full, e.g. `cpp('pinMode(13, OUTPUT);');`.",
      );

  static Diagnostic cppPosition(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.cppMisuse,
        location: at,
        message: 'cpp() can only be used as a statement of its own.',
        suggestion: 'Move it to its own line, e.g. into the loop body.',
      );

  static Diagnostic cppHeap(String word, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.cppHeap,
        location: at,
        message: "the C++ text uses '$word', which "
            '${word == 'free' || word == 'delete' ? 'frees heap memory' : 'allocates on the heap'}. Generated code '
            'must not use the heap.',
        suggestion: "Allocate statically instead, e.g. a global array: `cpp('static char buffer[16];');`.",
      );

  static Diagnostic pinOutOfRange(String value, String widget, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedArgument,
        location: at,
        message: 'pin $value is out of range for $widget: the Uno has pins 0 to 19 (D0–D13, and A0–A5 as 14–19).',
        suggestion: 'Pass a pin from 0 to 19, e.g. `13` or `A0`.',
      );

  // E021: widget program shape.

  static Diagnostic widgetProgramEntryPoint(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: "a widget program cannot also declare '$name()': main() and runDevice() generate setup() and loop().",
        suggestion: 'Remove it and put the code in widget callbacks, e.g. '
            '`Every(Duration(milliseconds: 100), () { … })`.',
      );

  /// [what] is `the widget 'Led'`, `Device(…)`, `runDevice()`, ….
  static Diagnostic widgetOutsideWidgetProgram(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: '$what can only be used in a widget program, which has `void main() => runDevice(…)` instead of '
            'setup() and loop().',
        suggestion: 'Describe the device in main(), e.g. '
            '`void main() => runDevice(Device(board: Uno(), children: [Led(pin: 13)]));`, and remove setup() and '
            'loop(); or use pinMode() and digitalWrite() directly.',
      );

  /// [what] is `runDevice()`, `Device(…)`, or `Uno()`.
  static Diagnostic deviceOutsideMain(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: '$what can only be written in main(), as `runDevice(Device(board: Uno(), children: […]))`.',
        suggestion: 'Move it into `void main() => runDevice(Device(…));`; the compiler reads main() statically.',
      );

  static Diagnostic deviceBoard(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: 'the board must be written as `Uno()`, the only board in this version.',
        suggestion: 'Write `board: Uno()`.',
      );

  static Diagnostic deviceChildrenNotLiteral(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: 'children must be a list literal written in place, e.g. `children: [led, button]`.',
        suggestion: 'List the widgets directly inside `Device(children: [...])`; the compiler reads it statically.',
      );

  /// [what] is `a spread (...)`, `a collection if`, `a collection for`, or a description of the element.
  static Diagnostic deviceChildElement(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: '$what is not supported in children: each element is a top-level widget or a widget constructor.',
        suggestion: 'List every widget on its own, e.g. `children: [led, Led(pin: 3)]`.',
      );

  static Diagnostic serialBeginInWidgetProgram(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: 'a widget program cannot call Serial.begin(): the generated setup() opens Serial before anything '
            'else runs.',
        suggestion: 'Remove it, and set the speed with `Device(serialBaud: 115200, …)` if 9600 baud does not fit.',
      );

  static Diagnostic serialBaudNotConstant(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetProgram,
        location: at,
        message: 'serialBaud must be a compile-time constant.',
        suggestion: 'Use a literal or a `const`, e.g. `serialBaud: 115200`.',
      );

  // E022: widget rules.

  static Diagnostic widgetPlacement(String widget, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: 'a widget ($widget) can only be a top-level `final` or be written directly in Device.children.',
        suggestion: 'Declare it at the top level, e.g. `final ${lowerFirst(widget)} = $widget(…);`, and list it in '
            'children.',
      );

  static Diagnostic widgetNotFinal(String name, String example, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: "the widget '$name' must be declared `final`.",
        suggestion: 'Write `$example`. Each widget is one C++ object, created once.',
      );

  /// [what] is `the pin of Led`.
  static Diagnostic widgetArgumentNotConstant(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: '$what must be a compile-time constant.',
        suggestion: 'Use a literal or a `const`, e.g. `const int ledPin = 13;`.',
      );

  /// [owner] is `'alarm' (line 5)` or `the Led on line 12`.
  static Diagnostic duplicatePin(int pin, String owner, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: 'pin $pin is already used by $owner.',
        suggestion: 'Give each widget its own pin.',
      );

  static Diagnostic widgetNotInChildren(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: "the widget '$name' is not listed in Device.children, so it would never be set up or polled.",
        suggestion: 'Add `$name` to `children: [...]` in main().',
      );

  static Diagnostic widgetListedTwice(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: "the widget '$name' is listed in Device.children more than once.",
        suggestion: 'List each widget once; the children order is the order of setup and polling.',
      );

  static Diagnostic widgetUsedBeforeDeclaration(String owner, String used, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: "the callback of '$owner' uses the widget '$used', which is declared below it.",
        suggestion: "Move the declaration of '$used' above '$owner'.",
      );

  static Diagnostic widgetHandleUse(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: "the widget '$name' can only be used to call its methods or be listed in Device.children.",
        suggestion:
            'Call a method on it directly, e.g. `$name.toggle()`, instead of storing, comparing, or passing it.',
      );

  /// [position] is `a parameter`, `a local variable`, `a return value`.
  static Diagnostic widgetTypePosition(String position, String type, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: "$position of the widget type '$type' is not supported. Widgets can only be top-level `final`s.",
        suggestion: 'Use the top-level widget directly instead of passing it around.',
      );

  static Diagnostic intervalNotDuration(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: 'the interval of Every must be written in place as `Duration(…)`.',
        suggestion: 'Write it in the call, e.g. `Every(Duration(milliseconds: 500), () { … })`.',
      );

  static Diagnostic intervalNotConstant(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message: 'the interval of Every must be a compile-time constant.',
        suggestion: 'Use literals or `const` ints, e.g. `Duration(milliseconds: blinkMs)` with '
            '`const int blinkMs = 500;`.',
      );

  /// [microseconds] is the interval's exact length.
  static Diagnostic intervalOutOfRange(int microseconds, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.widgetRule,
        location: at,
        message:
            'the interval of Every is ${microseconds % 1000 == 0 ? '${microseconds ~/ 1000} ms' : '$microseconds µs'}'
            ', but it must be a whole number of milliseconds from 1 to 2147483647 (about 24.8 days).',
        suggestion: 'Use whole milliseconds in that range, e.g. `Duration(milliseconds: 500)`.',
      );

  static String _article(String word) => word.startsWith('uint') || !'aeiou'.contains(word[0]) ? 'a' : 'an';
}

/// `[a]` → `a`; `[a, b]` → `a and b`; `[a, b, c]` → `a, b, and c`.
String englishList(List<String> items) => switch (items) {
      [] => 'none',
      [final only] => only,
      [final a, final b] => '$a and $b',
      [...final init, final last] => '${init.join(', ')}, and $last',
    };

/// `SoftSerial` → `softSerial`.
String lowerFirst(String name) => name.isEmpty ? name : name[0].toLowerCase() + name.substring(1);
