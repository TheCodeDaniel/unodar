import 'codes.dart';
import 'diagnostic.dart';

/// Factories for every diagnostic. All user-facing wording lives here.
///
/// Message style: lower-case start, states what is wrong in the user's terms. Suggestion style: an imperative
/// sentence saying what to do instead.
abstract final class Diagnostics {
  static Diagnostic missingEntryPoint(String name, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.missingEntryPoint,
        location: at,
        message: "missing required function '$name()'. Every unodar sketch needs both setup() and loop().",
        suggestion: 'Add `void $name() { }` at the top level of this file.',
      );

  static Diagnostic unsupportedStatement(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedStatement,
        location: at,
        message: '$what is not supported in this version. Only calls to unodar API functions are allowed here.',
        suggestion: 'Rewrite this as a sequence of pinMode/digitalWrite/delay calls; see docs/SUBSET.md.',
      );

  static Diagnostic unknownFunction(String name, List<String> supported, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unknownFunction,
        location: at,
        message: "unknown function '$name'. Only ${englishList(supported)} are supported in this version.",
        suggestion: 'Remove this call. More Arduino functions arrive in a later phase; see docs/SUBSET.md.',
      );

  static Diagnostic unsupportedArgument(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedArgument,
        location: at,
        message: '$what is not supported as an argument. Only integer literals and unodar constants are allowed.',
        suggestion:
            'Use a literal such as `13` or a constant such as `HIGH`, `LOW`, `OUTPUT`, `INPUT`, `INPUT_PULLUP`.',
      );

  static Diagnostic unsupportedDeclaration(String what, SourceLocation at) => Diagnostic(
        code: DiagnosticCode.unsupportedDeclaration,
        location: at,
        message: '$what is not supported in this version. Only `void setup()` and `void loop()` may be declared.',
        suggestion: 'Remove this declaration and inline its use into setup() or loop().',
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
}

/// `[a]` → `a`; `[a, b]` → `a and b`; `[a, b, c]` → `a, b, and c`.
String englishList(List<String> items) => switch (items) {
      [] => 'none',
      [final only] => only,
      [final a, final b] => '$a and $b',
      [...final init, final last] => '${init.join(', ')}, and $last',
    };
