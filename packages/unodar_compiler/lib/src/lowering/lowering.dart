import 'package:analyzer/dart/ast/ast.dart';

import '../api/api_registry.dart';
import '../api/api_resolution.dart';
import '../frontend/frontend.dart';
import '../ir/ir.dart';
import '../validator/rules.dart';

/// Thrown when lowering meets a construct the validator should have rejected. Always a compiler bug (exit code 2),
/// never a user error: it means a validator rule and the lowering disagree about the subset.
final class LoweringError extends Error {
  LoweringError(this.message);

  final String message;

  @override
  String toString() => 'internal compiler error during lowering: $message';
}

/// Lowers a **validated** source to IR. Dart names become C++ names here, via the [ApiRegistry].
///
/// Lowering is deliberately strict: rather than guess at anything unexpected, it throws [LoweringError]. Together
/// with the validator this upholds "reject loudly, never miscompile".
final class Lowering {
  const Lowering(this.api);

  final ApiRegistry api;

  IrProgram lower(ResolvedSource source) => IrProgram(
        sourceName: source.displayName,
        functions: [for (final function in entryPoints(source.unit)) _function(function, source)],
      );

  IrFunction _function(FunctionDeclaration function, ResolvedSource source) {
    final body = function.functionExpression.body;
    if (body is! BlockFunctionBody) throw LoweringError('${function.name.lexeme} has no block body');
    return IrFunction(
      name: function.name.lexeme,
      line: _line(source, function.firstTokenAfterCommentAndMetadata.offset),
      body: [for (final statement in body.block.statements) _statement(statement, source)],
    );
  }

  IrStatement _statement(Statement statement, ResolvedSource source) {
    if (statement case ExpressionStatement(expression: final MethodInvocation call)) {
      final function = api.resolveCall(call) ?? (throw LoweringError('unresolved call ${call.toSource()}'));
      return IrCall(
        function.cppName,
        [for (final argument in call.argumentList.arguments) _argument(argument)],
        line: _line(source, statement.offset),
      );
    }
    throw LoweringError('unsupported statement ${statement.toSource()}');
  }

  IrExpression _argument(Argument argument) {
    if (argument is IntegerLiteral && argument.value != null) return IrIntLiteral(argument.value!);
    if (argument is Expression) {
      final constant = api.resolveConstant(argument);
      if (constant != null) return IrConstant(constant.cppName);
    }
    throw LoweringError('unsupported argument ${argument.toSource()}');
  }

  int _line(ResolvedSource source, int offset) => source.lineInfo.getLocation(offset).lineNumber;
}
