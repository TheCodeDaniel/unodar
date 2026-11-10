import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Human-readable names for AST constructs, used in diagnostic messages ("an if statement is not supported…").
///
/// Unknown kinds fall back to a generic phrase rather than failing: a vague message is acceptable, a crash is not.
String describeStatement(Statement statement) => switch (statement) {
      IfStatement() => 'an if statement',
      ForStatement() => 'a for loop',
      WhileStatement() => 'a while loop',
      DoStatement() => 'a do-while loop',
      SwitchStatement() => 'a switch statement',
      ReturnStatement() => 'a return statement',
      VariableDeclarationStatement() => 'a local variable declaration',
      FunctionDeclarationStatement() => 'a local function',
      Block() => 'a nested block',
      EmptyStatement() => 'an empty statement (`;`)',
      TryStatement() => 'a try statement',
      BreakStatement() => 'a break statement',
      ContinueStatement() => 'a continue statement',
      AssertStatement() => 'an assert statement',
      YieldStatement() => 'a yield statement',
      LabeledStatement() => 'a labeled statement',
      PatternVariableDeclarationStatement() => 'a pattern variable declaration',
      ExpressionStatement(:final expression) => describeExpression(expression),
      _ => 'this statement',
    };

String describeExpression(Expression expression) => switch (expression) {
      StringLiteral() => 'a string literal',
      DoubleLiteral() => 'a double literal',
      BooleanLiteral() => 'a boolean literal',
      NullLiteral() => 'null',
      PrefixExpression(operator: Token(lexeme: '-'), operand: IntegerLiteral()) => 'a negative number',
      PrefixExpression() => 'a prefix expression',
      PostfixExpression() => 'a postfix expression',
      BinaryExpression() => 'an arithmetic or logical expression',
      ConditionalExpression() => 'a conditional (`?:`) expression',
      AssignmentExpression() => 'an assignment',
      ParenthesizedExpression() => 'a parenthesized expression',
      CascadeExpression() => 'a cascade expression',
      AwaitExpression() => 'an await expression',
      ThrowExpression() => 'a throw expression',
      FunctionExpression() => 'a closure',
      ListLiteral() || SetOrMapLiteral() || RecordLiteral() => 'a collection literal',
      InstanceCreationExpression() => 'a constructor call',
      MethodInvocation() || FunctionExpressionInvocation() => 'a function call',
      SimpleIdentifier() || PrefixedIdentifier() || PropertyAccess() => 'a variable reference',
      _ => 'this expression',
    };
