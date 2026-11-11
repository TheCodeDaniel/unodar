import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import '../ir/ir.dart';
import 'elements.dart';
import 'types.dart';

/// The outcome of evaluating an expression at compile time.
sealed class ConstantResult {
  const ConstantResult();
}

/// The expression is not a compile-time constant (it reads a variable, calls a function, …).
final class NotConstant extends ConstantResult {
  const NotConstant();
}

/// The expression is a constant with this Dart value (`int`, `double`, or `bool`).
final class ConstantValue extends ConstantResult {
  const ConstantValue(this.value);

  final Object value;
}

/// The expression is constant, but its value cannot be represented exactly in C++ (E010).
sealed class ConstantProblem extends ConstantResult {
  const ConstantProblem();
}

/// An integer literal outside `int32_t`. Reported at the literal itself.
final class IntegerLiteralOutOfRange extends ConstantProblem {
  const IntegerLiteralOutOfRange(this.literal);

  final IntegerLiteral literal;
}

/// A double literal outside `float`. Reported at the literal itself.
final class DoubleLiteralOutOfRange extends ConstantProblem {
  const DoubleLiteralOutOfRange(this.literal);

  final DoubleLiteral literal;
}

/// An intermediate `int` result outside `int32_t`. Reported at the evaluated expression.
final class ConstantOverflow extends ConstantProblem {
  const ConstantOverflow(this.value);

  final int value;
}

/// `~/`, `%`, or `/` by a constant zero. Reported at the evaluated expression.
final class ConstantDivisionByZero extends ConstantProblem {
  const ConstantDivisionByZero();
}

/// Evaluates constant expressions with **Dart semantics** (Dart's own operators on 64-bit `int` and `double`) and
/// checks every intermediate `int` against the `int32_t` range that unodar compiles `int` to (docs/SUBSET.md
/// "Constant expressions are checked").
///
/// Constants are literals, unodar constants, `const` variables (top-level or local), `Uint8(…)`/`Uint16(…)`/
/// `Int16(…)` of constants, and the supported operators over them. Values of referenced `const` variables come
/// from the analyzer and are not range-checked again here: their own initializers are checked where declared.
///
/// Evaluation is strict (both sides of `&&`, `||`, and both branches of `?:` are evaluated), so a problem anywhere
/// in a constant expression is reported even if Dart would not evaluate that part.
final class ConstantEvaluator {
  const ConstantEvaluator();

  static const int32Min = -2147483648;
  static const int32Max = 2147483647;

  /// The largest finite `float`.
  static const floatMax = 3.4028234663852886e38;

  ConstantResult evaluate(Expression expression) {
    try {
      return ConstantValue(_eval(expression));
    } on _NotConstant {
      return const NotConstant();
    } on _Problem catch (problem) {
      return problem.result;
    }
  }

  /// The value of [expression] if it is a constant without problems, else null.
  Object? valueOf(Expression expression) => switch (evaluate(expression)) {
        ConstantValue(:final value) => value,
        _ => null,
      };

  Object _eval(Expression e) {
    switch (e) {
      case IntegerLiteral(:final value):
        if (value == null) throw const _NotConstant();
        // An integer literal in a double context (`double d = 1;`) is a double in Dart.
        if (e.staticType?.isDartCoreDouble ?? false) return value.toDouble();
        if (value > int32Max) throw _Problem(IntegerLiteralOutOfRange(e));
        return value;
      case DoubleLiteral(:final value):
        if (value.abs() > floatMax) throw _Problem(DoubleLiteralOutOfRange(e));
        return value;
      case BooleanLiteral(:final value):
        return value;
      case SimpleIdentifier():
        return _reference(e);
      case ParenthesizedExpression(:final expression):
        return _eval(expression);
      case PrefixExpression(:final operator, :final operand):
        final value = _eval(operand);
        return switch ((operator.type, value)) {
          (TokenType.MINUS, final int v) => _int(-v),
          (TokenType.MINUS, final double v) => -v,
          (TokenType.BANG, final bool v) => !v,
          _ => throw const _NotConstant(),
        };
      case BinaryExpression(:final operator, :final leftOperand, :final rightOperand):
        return _binary(operator.type, _eval(leftOperand), _eval(rightOperand));
      case ConditionalExpression(:final condition, :final thenExpression, :final elseExpression):
        final test = _eval(condition);
        final then = _eval(thenExpression);
        final otherwise = _eval(elseExpression);
        if (test is! bool) throw const _NotConstant();
        return test ? then : otherwise;
      case InstanceCreationExpression(:final argumentList):
        final type = sizedTypeOf(e.staticType!);
        if (type == null || argumentList.arguments.length != 1) throw const _NotConstant();
        final value = _eval(argumentList.arguments.single.argumentExpression);
        if (value is! int) throw const _NotConstant();
        return wrapSized(type, value);
      default:
        throw const _NotConstant();
    }
  }

  Object _reference(SimpleIdentifier identifier) {
    final VariableElement? element = switch (referenceOf(identifier)) {
      UnodarConstantReference(:final element) || GlobalReference(:final element) => element,
      LocalReference(:final element) => element,
      _ => null,
    };
    if (element == null || !element.isConst) throw const _NotConstant();
    return _fromDartObject(element.computeConstantValue()) ?? (throw const _NotConstant());
  }

  static Object? _fromDartObject(DartObject? object) =>
      object?.toIntValue() ?? object?.toDoubleValue() ?? object?.toBoolValue();

  Object _binary(TokenType operator, Object left, Object right) {
    if (left is bool && right is bool) {
      return switch (operator) {
        TokenType.AMPERSAND_AMPERSAND => left && right,
        TokenType.BAR_BAR => left || right,
        TokenType.EQ_EQ => left == right,
        TokenType.BANG_EQ => left != right,
        _ => throw const _NotConstant(),
      };
    }
    if (left is! num || right is! num) throw const _NotConstant();
    switch (operator) {
      case TokenType.EQ_EQ:
        return left == right;
      case TokenType.BANG_EQ:
        return left != right;
      case TokenType.LT:
        return left < right;
      case TokenType.LT_EQ:
        return left <= right;
      case TokenType.GT:
        return left > right;
      case TokenType.GT_EQ:
        return left >= right;
      case TokenType.SLASH:
        if (right == 0) throw const _Problem(ConstantDivisionByZero());
        return left / right;
      default:
    }
    if (left is int && right is int) {
      return switch (operator) {
        TokenType.PLUS => _int(left + right),
        TokenType.MINUS => _int(left - right),
        TokenType.STAR => _int(left * right),
        TokenType.TILDE_SLASH => right == 0 ? throw const _Problem(ConstantDivisionByZero()) : _int(left ~/ right),
        TokenType.PERCENT => right == 0 ? throw const _Problem(ConstantDivisionByZero()) : _int(left % right),
        _ => throw const _NotConstant(),
      };
    }
    // Mixed int/double arithmetic is double arithmetic, as in Dart. (`%`/`~/` on doubles are rejected, E002.)
    final (l, r) = (left.toDouble(), right.toDouble());
    return switch (operator) {
      TokenType.PLUS => l + r,
      TokenType.MINUS => l - r,
      TokenType.STAR => l * r,
      _ => throw const _NotConstant(),
    };
  }

  static int _int(int value) => value < int32Min || value > int32Max ? throw _Problem(ConstantOverflow(value)) : value;

  /// The Dart value of `Uint8(value)` etc., exactly as `package:unodar` defines it.
  static int wrapSized(IrType type, int value) => switch (type) {
        IrType.uint8 => value & 0xFF,
        IrType.uint16 => value & 0xFFFF,
        IrType.int16 => ((value + 0x8000) & 0xFFFF) - 0x8000,
        _ => throw ArgumentError(type),
      };
}

final class _NotConstant implements Exception {
  const _NotConstant();
}

final class _Problem implements Exception {
  const _Problem(this.result);

  final ConstantProblem result;
}
