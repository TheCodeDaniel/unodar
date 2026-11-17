import 'package:analyzer/dart/ast/ast.dart';

import '../api/api_resolution.dart';
import '../diagnostics/diagnostics.dart';
import '../semantics/enums.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import 'rules.dart';

/// The user's enums are simple enums of at most 256 values (E028); printing a value is E009 (docs/SUBSET.md
/// "Enums"). `Mode.values` and `mode.name` are reported by the expression rule, through [expressionIssue].
final class EnumRule implements ValidationRule {
  const EnumRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final declaration in userEnumDeclarations(unit)) {
      final name = declaration.namePart.typeName;
      final values = [for (final c in declaration.body.constants) c.name.lexeme];
      if (!isSimpleEnum(declaration)) {
        context.report(Diagnostics.enhancedEnum(name.lexeme, values, context.at(name)));
      } else if (values.length > 256) {
        context.report(Diagnostics.tooManyEnumValues(name.lexeme, values.length, context.at(name)));
      }
    }
    // `Serial.print(mode)`: Dart prints `Mode.heating`; there are no strings on the device.
    for (final root in allRootExpressions(unit)) {
      for (final call in subexpressions(root).whereType<MethodInvocation>()) {
        if (!_isPrint(call, context)) continue;
        final value = call.argumentList.arguments.where((a) => a is! NamedArgument).firstOrNull?.argumentExpression;
        if (value != null && userEnumOf(value.staticType) != null) {
          context.report(Diagnostics.enumPrint(value.toSource(), context.at(value)));
        }
      }
    }
  }

  static bool _isPrint(MethodInvocation call, ValidationContext context) =>
      context.api.resolveMethodCall(call)?.method.parameters.firstOrNull?.isPrintable ?? false;
}
