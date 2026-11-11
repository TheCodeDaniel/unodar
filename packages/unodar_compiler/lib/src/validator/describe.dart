import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Human-readable names and suggestions for AST constructs, used in diagnostic messages ("a do-while loop is not
/// supported in this version.").
///
/// Unknown kinds fall back to a generic phrase rather than failing: a vague message is acceptable, a crash is not.

const genericHelp = 'See docs/SUBSET.md for the supported statements and expressions.';
const removeLabel = 'Remove the label; only unlabeled `break` and `continue` are supported.';
const compoundAssignmentHelp =
    'Write the assignment out in full, e.g. `x = x * y;`. Only `=`, `+=`, and `-=` are supported.';
const incrementHelp = 'Use `++` and `--` only as statements of their own, e.g. `count++;` on its own line.';
const bitwiseHelp = 'Bitwise and shift operators arrive in a later phase; use arithmetic instead.';

/// What a rejected statement is called, and what to do instead.
(String, String) describeUnsupportedStatement(Statement statement) => switch (statement) {
      DoStatement() => ('a do-while loop', 'Use a `while` loop instead.'),
      SwitchStatement() => ('a switch statement', 'Use `if` / `else if` instead.'),
      LabeledStatement() => ('a labeled statement', removeLabel),
      TryStatement() => ('a try statement', 'Exceptions are not supported on the device; remove it.'),
      AssertStatement() => ('an assert statement', 'Asserts are not supported on the device; remove it.'),
      YieldStatement() => ('a yield statement', 'Generators are not supported; return a value instead.'),
      EmptyStatement() => ('an empty statement (`;`)', 'Remove the stray `;`.'),
      PatternVariableDeclarationStatement() => ('a pattern variable declaration', 'Declare one variable at a time.'),
      _ => ('this statement', genericHelp),
    };

String describeExpression(Expression expression) => switch (expression) {
      StringLiteral() => 'a string literal',
      NullLiteral() => 'null',
      CascadeExpression() => 'a cascade expression',
      AwaitExpression() => 'an await expression',
      ThrowExpression() => 'a throw expression',
      ListLiteral() || SetOrMapLiteral() || RecordLiteral() => 'a collection literal',
      FunctionExpressionInvocation() => 'a call of a function value',
      SwitchExpression() => 'a switch expression',
      IndexExpression() => 'an index expression (`[]`)',
      PrefixExpression(operator: Token(lexeme: final op)) => 'the `$op` operator',
      _ => 'this expression',
    };
