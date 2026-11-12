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

  static Diagnostic unknownFunction(String name, List<String> apiFunctions, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unknownFunction,
        location: at,
        message: "unknown function '$name'. Only functions declared in this file and the unodar API functions "
            '${englishList(apiFunctions)} can be called in this version.',
        suggestion: 'Declare the function in this file, or remove this call. More Arduino functions arrive in a later '
            'phase; see docs/SUBSET.md.',
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

  static Diagnostic reservedMain(SourceLocation at) => Diagnostic(
        code: DiagnosticCode.reservedMain,
        location: at,
        message: "'main()' is reserved for the widget API (runDevice), which arrives in a later phase.",
        suggestion: 'Remove main() and put your code in `void setup()` and `void loop()` instead.',
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
