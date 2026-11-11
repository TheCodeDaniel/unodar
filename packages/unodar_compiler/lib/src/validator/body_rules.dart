import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import '../diagnostics/diagnostics.dart';
import '../ir/ir.dart';
import '../semantics/constant_evaluator.dart';
import '../semantics/elements.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import 'describe.dart';
import 'rules.dart';

/// Statement kinds and statement-level expression forms (E002), local functions (E012).
final class StatementRule implements ValidationRule {
  const StatementRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final function in compiledFunctions(unit)) {
      final body = function.functionExpression.body;
      if (isVoidArrow(function)) _statementLevel((body as ExpressionFunctionBody).expression, context);
      for (final statement in statementsIn(body)) {
        _statement(statement, context);
      }
    }
  }

  void _statement(Statement statement, ValidationContext context) {
    void unsupported(String what, String help) =>
        context.report(Diagnostics.unsupportedStatement(what, help, context.at(statement)));
    switch (statement) {
      case Block() || IfStatement() || WhileStatement() || ReturnStatement():
        break;
      case BreakStatement(label: null) || ContinueStatement(label: null):
        break;
      case BreakStatement() || ContinueStatement():
        unsupported(statement is BreakStatement ? 'a labeled break' : 'a labeled continue', removeLabel);
      case VariableDeclarationStatement(:final variables) when variables.isLate:
        unsupported('a late local variable', 'Remove `late`; `int x;` followed by an assignment already works.');
      case VariableDeclarationStatement():
        break;
      case ForStatement(:final forLoopParts):
        switch (forLoopParts) {
          case ForPartsWithDeclarations(:final variables) when variables.variables.length > 1:
            unsupported('a for loop that declares more than one variable', 'Declare the extra variables before it.');
          case ForPartsWithDeclarations(:final variables) when variables.isLate:
            unsupported('a late loop variable', 'Remove `late`.');
          case ForPartsWithDeclarations() || ForPartsWithExpression():
            statementLevelExpressions(statement).forEach((e) => _statementLevel(e, context));
          case ForEachParts():
            unsupported('a for-in loop', 'Use a counting loop instead: `for (int i = 0; i < n; i++) { ... }`.');
          default:
            unsupported('a pattern in a for loop', genericHelp);
        }
      case ExpressionStatement(:final expression):
        _statementLevel(expression, context);
      case FunctionDeclarationStatement(:final functionDeclaration):
        context.report(Diagnostics.localFunction(functionDeclaration.name.lexeme, context.at(statement)));
      default:
        final (what, help) = describeUnsupportedStatement(statement);
        unsupported(what, help);
    }
  }

  /// A call, `x = e`, `x += e`, `x -= e`, `x++`, `x--`, `++x`, `--x`, where `x` is a plain variable name.
  void _statementLevel(Expression expression, ValidationContext context) {
    void unsupported(String what, String help) =>
        context.report(Diagnostics.unsupportedStatement(what, help, context.at(expression)));
    switch (expression) {
      case MethodInvocation():
        break;
      case AssignmentExpression(:final operator) when !supportedAssignmentOperators.contains(operator.type):
        unsupported('the `${operator.lexeme}` operator', compoundAssignmentHelp);
      case AssignmentExpression(:final leftHandSide) when leftHandSide is! SimpleIdentifier:
        unsupported('an assignment to `${leftHandSide.toSource()}`', 'Assign to a variable name.');
      case AssignmentExpression():
        break;
      case PrefixExpression(:final operand) || PostfixExpression(:final operand)
          when isIncrementOrDecrement(expression):
        if (operand is! SimpleIdentifier) {
          unsupported('`++`/`--` on `${operand.toSource()}`', 'Apply `++` and `--` to a variable name.');
        }
      case ThrowExpression():
        unsupported('a throw expression', 'Exceptions are not supported on the device; remove it.');
      default:
        unsupported('an expression statement that is not a call or an assignment',
            'Remove it, or turn it into a call or an assignment.');
    }
  }
}

/// Expression kinds and operators in value positions (E002), closures and function references (E012).
final class ExpressionRule implements ValidationRule {
  const ExpressionRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final root in allRootExpressions(unit)) {
      walkExpression(root, (expression) {
        final issue = expressionIssue(expression);
        if (issue == null) return true;
        context.report(issue(context.at(expression)));
        return false;
      });
    }
  }
}

/// The diagnostic for [expression] if its kind or operator is outside the subset, as a function of its location.
/// Shared by every rule that must skip what [ExpressionRule] reports.
Diagnostic Function(SourceLocation)? expressionIssue(Expression expression) {
  Diagnostic Function(SourceLocation) e002(String what, String help) =>
      (at) => Diagnostics.unsupportedStatement(what, help, at);
  switch (expression) {
    case IntegerLiteral() || DoubleLiteral() || BooleanLiteral():
    case ParenthesizedExpression() || ConditionalExpression() || MethodInvocation():
      return null;
    case SimpleIdentifier():
      return switch (referenceOf(expression)) {
        FunctionValueReference() => (at) => Diagnostics.functionReference(expression.name, at),
        null => e002("the name '${expression.name}'", genericHelp),
        _ => null,
      };
    case PrefixExpression(:final operator):
      return switch (operator.type) {
        TokenType.MINUS || TokenType.BANG => null,
        TokenType.PLUS_PLUS ||
        TokenType.MINUS_MINUS =>
          e002('`${operator.lexeme}` inside an expression', incrementHelp),
        _ => e002('the `${operator.lexeme}` operator', bitwiseHelp),
      };
    case PostfixExpression(:final operator):
      return isIncrementOrDecrement(expression)
          ? e002('`${operator.lexeme}` inside an expression', incrementHelp)
          : e002('a null check (`!`)', 'Nullable values are not supported, so the check is never needed.');
    case BinaryExpression(:final operator, :final leftOperand, :final rightOperand):
      final type = operator.type;
      if (type == TokenType.PERCENT || type == TokenType.TILDE_SLASH) {
        final integers =
            irTypeOf(leftOperand.staticType)?.isInteger == true && irTypeOf(rightOperand.staticType)?.isInteger == true;
        if (!integers) {
          return e002('the `${operator.lexeme}` operator on a double',
              'C++ has no operator that matches it. Use ints, or compute it with `/` and `-`.');
        }
        return null;
      }
      if (supportedBinaryOperators.contains(type)) return null;
      if (type == TokenType.QUESTION_QUESTION) {
        return e002('the `??` operator', 'Nullable values are not supported, so `??` is never needed.');
      }
      return e002('the `${operator.lexeme}` operator', bitwiseHelp);
    case InstanceCreationExpression(:final staticType):
      return staticType != null && sizedTypeOf(staticType) != null
          ? null
          : e002('a constructor call', 'Only Uint8(…), Uint16(…), and Int16(…) can be constructed in this version.');
    case FunctionExpression():
      return Diagnostics.closure;
    case FunctionReference():
      return (at) => Diagnostics.functionReference(expression.function.toSource(), at);
    case AssignmentExpression():
      return e002('an assignment inside an expression', 'Assign in a statement of its own, then use the variable.');
    case PrefixedIdentifier() || PropertyAccess():
      return e002("a property access ('${expression.toSource()}')",
          'Properties and methods of values are not supported in this version.');
    case StringLiteral():
      return e002('a string literal', 'Strings arrive with Serial in Phase 3.');
    case IsExpression() || AsExpression():
      return e002(expression is IsExpression ? 'a type test (`is`)' : 'a cast (`as`)',
          'Declare the variable with the type you need instead.');
    default:
      return e002(describeExpression(expression), genericHelp);
  }
}

/// The binary operators of the subset (`%` and `~/` additionally need integer operands).
const supportedBinaryOperators = {
  TokenType.PLUS,
  TokenType.MINUS,
  TokenType.STAR,
  TokenType.SLASH,
  TokenType.TILDE_SLASH,
  TokenType.PERCENT,
  TokenType.EQ_EQ,
  TokenType.BANG_EQ,
  TokenType.LT,
  TokenType.LT_EQ,
  TokenType.GT,
  TokenType.GT_EQ,
  TokenType.AMPERSAND_AMPERSAND,
  TokenType.BAR_BAR,
};

/// The static type of every supported expression must be supported (E009), and `==`/`!=` must not compare a bool
/// with a number (E009). Nodes that [ExpressionRule] or [ApiCallRule] report are skipped.
final class ExpressionTypeRule implements ValidationRule {
  const ExpressionTypeRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final genericFunctions = {
      for (final f in compiledFunctions(unit))
        if (f.functionExpression.typeParameters != null) f,
    };
    final roots = [
      for (final variable in topLevelVariables(unit))
        if (variable.initializer case final initializer?) initializer,
      for (final function in compiledFunctions(unit))
        if (!genericFunctions.contains(function)) ...rootsOfFunction(function),
    ];
    for (final root in roots) {
      walkExpression(root, (expression) {
        if (expressionIssue(expression) != null) return false;
        if (expression is MethodInvocation && expression.target != null) return false;
        final type = expression.staticType;
        // An unresolved name has no real type; the analyzer (E007) or ApiCallRule (E003) reports it.
        if (type is InvalidType) return false;
        if (type == null || irTypeOf(type) == null) {
          if (type != null) {
            context.report(
                typeDiagnostic(type, context.at(expression), isConditional: expression is ConditionalExpression));
          }
          return false;
        }
        if (expression case BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
            when operator.type == TokenType.EQ_EQ || operator.type == TokenType.BANG_EQ) {
          final (l, r) = (irTypeOf(leftOperand.staticType), irTypeOf(rightOperand.staticType));
          if ((l == IrType.bool_ && r != null && r.isNumeric) || (r == IrType.bool_ && l != null && l.isNumeric)) {
            context.report(Diagnostics.boolNumberComparison(context.at(expression)));
            return false;
          }
        }
        return true;
      });
    }
  }
}

/// Every call must resolve to a function declared in this file or a supported unodar API function (E003).
final class ApiCallRule implements ValidationRule {
  const ApiCallRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final call in allCalls(unit)) {
      if (context.api.resolveCall(call) != null || userFunctionOf(call) != null) continue;
      final target = call.target;
      final name = target == null ? call.methodName.name : '${target.toSource()}.${call.methodName.name}';
      context.report(Diagnostics.unknownFunction(name, context.api.functionNames, context.at(call.methodName)));
    }
  }
}

/// Every call in a supported position, in source order.
Iterable<MethodInvocation> allCalls(CompilationUnit unit) =>
    allRootExpressions(unit).expand(subexpressions).whereType<MethodInvocation>();

/// Arguments to unodar API functions: constants must fit the Arduino parameter type; no named arguments (E004).
/// Arguments of calls that already got E003 are not checked.
final class ArgumentRule implements ValidationRule {
  const ArgumentRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final call in allCalls(unit)) {
      final function = context.api.resolveCall(call);
      if (function == null) continue;
      final positional = function.positionalParameters;
      var index = 0;
      for (final argument in call.argumentList.arguments) {
        if (argument is NamedArgument) {
          context.report(Diagnostics.namedArgument(argument.name.lexeme, function.dartName, context.at(argument)));
          continue;
        }
        if (index >= positional.length) continue; // An analyzer error (too many arguments) already.
        final parameter = positional[index++];
        final value = context.constants.valueOf(argument.argumentExpression);
        if (value is int && (value < parameter.min || value > parameter.max)) {
          context.report(Diagnostics.argumentOutOfRange('$value', parameter.name, function.dartName, parameter.cppType,
              '${parameter.min} to ${parameter.max}', context.at(argument)));
        }
      }
    }
  }
}

/// Every maximal constant subexpression must be representable exactly: int32 range, float range, no constant
/// division by zero (E010).
final class ConstantRangeRule implements ValidationRule {
  const ConstantRangeRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final root in allRootExpressions(unit)) {
      walkExpression(root, (expression) {
        switch (context.constants.evaluate(expression)) {
          case NotConstant():
            return true;
          case ConstantValue():
            return false;
          case IntegerLiteralOutOfRange(:final literal):
            context.report(Diagnostics.integerLiteralOutOfRange(literal.literal.lexeme, context.at(literal)));
          case DoubleLiteralOutOfRange(:final literal):
            context.report(Diagnostics.doubleLiteralOutOfRange(literal.literal.lexeme, context.at(literal)));
          case ConstantOverflow(:final value):
            context.report(Diagnostics.constantOverflow(value, context.at(expression)));
          case ConstantDivisionByZero():
            context.report(Diagnostics.constantDivisionByZero(context.at(expression)));
        }
        return false;
      });
    }
  }
}
