import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

import 'elements.dart';
import 'signals.dart';
import 'widgets.dart';

/// Traversal of the user's program in the shape the subset understands. Every validator rule and the lowering
/// walk the same positions, so a construct is either seen by all of them or by none.
///
/// Terms:
/// * a **statement-level expression** is the expression of an expression statement, a `for` initializer or
///   update, or the body of a `void f() => …;` function: a call, an assignment, or `++`/`--`;
/// * a **root expression** is a value position: an initializer, a condition, a returned value, a call statement,
///   an assignment's right-hand side;
/// * [childExpressions] descends only through supported expression kinds.

/// Every statement in [body], recursively, in source order (a statement before the statements it contains).
Iterable<Statement> statementsIn(FunctionBody body) sync* {
  if (body is BlockFunctionBody) yield* _statements(body.block);
}

Iterable<Statement> _statements(Statement statement) sync* {
  yield statement;
  for (final child in childStatements(statement)) {
    yield* _statements(child);
  }
}

/// The statements directly nested in [statement] that the subset compiles. Rejected statements (do, switch,
/// labeled, …) are not entered: they are reported once, as a whole.
List<Statement> childStatements(Statement statement) => switch (statement) {
      Block(:final statements) => statements,
      IfStatement(:final thenStatement, :final elseStatement) => [
          thenStatement,
          if (elseStatement != null) elseStatement
        ],
      WhileStatement(:final body) || ForStatement(:final body) => [body],
      _ => const [],
    };

/// The body of every compiled function, then of every widget callback (a callback is compiled like a `void`
/// function without parameters).
Iterable<FunctionBody> compiledBodies(CompilationUnit unit) sync* {
  for (final function in compiledFunctions(unit)) {
    yield function.functionExpression.body;
  }
  for (final callback in widgetCallbacks(unit)) {
    yield callback.body;
  }
}

/// The expression of an `=>` body whose value is discarded, so that it is statement-level: a `void f() => …;`
/// function or a widget callback. Null for a block body or a value-returning `=>` function.
Expression? statementLevelArrow(FunctionBody body) {
  if (body is! ExpressionFunctionBody) return null;
  return switch (body.parent) {
    FunctionExpression(parent: final FunctionDeclaration function) when isVoidArrow(function) => body.expression,
    FunctionExpression(parent: FunctionDeclaration()) => null,
    FunctionExpression() => body.expression, // A widget callback.
    _ => null,
  };
}

/// Every statement of every compiled function and callback, in source order per body.
Iterable<Statement> allStatements(CompilationUnit unit) sync* {
  for (final body in compiledBodies(unit)) {
    yield* statementsIn(body);
  }
}

/// Whether [function] has a `void` return type and an `=>` body, whose expression is then statement-level.
bool isVoidArrow(FunctionDeclaration function) =>
    function.functionExpression.body is ExpressionFunctionBody && function.returnType?.toSource() == 'void';

/// The statement-level expressions of [statement]: its expression, or a `for` loop's initializer and updates.
List<Expression> statementLevelExpressions(Statement statement) => switch (statement) {
      ExpressionStatement(:final expression) => [expression],
      ForStatement(forLoopParts: ForPartsWithExpression(:final initialization, :final updaters)) => [
          if (initialization != null) initialization,
          ...updaters,
        ],
      ForStatement(forLoopParts: ForPartsWithDeclarations(:final updaters)) => updaters,
      _ => const [],
    };

/// Every statement-level expression in the program.
Iterable<Expression> allStatementLevelExpressions(CompilationUnit unit) sync* {
  for (final body in compiledBodies(unit)) {
    if (statementLevelArrow(body) case final expression?) yield expression;
    for (final statement in statementsIn(body)) {
      yield* statementLevelExpressions(statement);
    }
  }
}

/// The assignment operators allowed as statements.
const supportedAssignmentOperators = {TokenType.EQ, TokenType.PLUS_EQ, TokenType.MINUS_EQ};

/// `x++`, `--x`, …
bool isIncrementOrDecrement(Expression expression) => switch (expression) {
      PrefixExpression(:final operator) ||
      PostfixExpression(:final operator) =>
        operator.type == TokenType.PLUS_PLUS || operator.type == TokenType.MINUS_MINUS,
      _ => false,
    };

/// The value positions inside a statement-level expression: a call itself, an assignment's right-hand side.
/// Statement-level forms the subset rejects contribute nothing here; the statement rule reports them.
List<Expression> rootsOfStatementLevel(Expression expression) => switch (expression) {
      MethodInvocation() => [expression],
      AssignmentExpression(:final operator, :final rightHandSide)
          when supportedAssignmentOperators.contains(operator.type) =>
        [rightHandSide],
      _ => const [],
    };

/// The root expressions of [statement] (not of nested statements).
List<Expression> rootsOf(Statement statement) => switch (statement) {
      ExpressionStatement(:final expression) => rootsOfStatementLevel(expression),
      VariableDeclarationStatement(:final variables) => [
          for (final variable in variables.variables)
            if (variable.initializer case final initializer?) initializer,
        ],
      IfStatement(:final expression) || WhileStatement(condition: final expression) => [expression],
      ForStatement(:final forLoopParts) => switch (forLoopParts) {
          ForPartsWithDeclarations(:final variables, :final condition, :final updaters) => [
              for (final variable in variables.variables)
                if (variable.initializer case final initializer?) initializer,
              if (condition != null) condition,
              ...updaters.expand(rootsOfStatementLevel),
            ],
          ForPartsWithExpression(:final initialization, :final condition, :final updaters) => [
              if (initialization != null) ...rootsOfStatementLevel(initialization),
              if (condition != null) condition,
              ...updaters.expand(rootsOfStatementLevel),
            ],
          _ => const [],
        },
      ReturnStatement(:final expression) => [if (expression != null) expression],
      _ => const [],
    };

/// Root expressions of one function body.
Iterable<Expression> rootsOfFunction(FunctionDeclaration function) => rootsOfBody(function.functionExpression.body);

/// Root expressions of one function or callback body.
Iterable<Expression> rootsOfBody(FunctionBody body) sync* {
  if (body is ExpressionFunctionBody) {
    final arrow = statementLevelArrow(body);
    yield* arrow != null ? rootsOfStatementLevel(arrow) : [body.expression];
  }
  for (final statement in statementsIn(body)) {
    yield* rootsOf(statement);
  }
}

/// Every root expression in the program: top-level initializers first, then the parts of a widget program's
/// `main()` that are compiled (the widgets written in `Device.children` and `serialBaud:`), then each function in
/// source order.
Iterable<Expression> allRootExpressions(CompilationUnit unit) sync* {
  for (final variable in topLevelVariables(unit)) {
    final initializer = variable.initializer;
    if (initializer != null) yield initializer;
  }
  yield* deviceRoots(unit);
  for (final body in compiledBodies(unit)) {
    yield* rootsOfBody(body);
  }
}

/// The operands of a supported expression kind. Unsupported kinds have no children here.
List<Expression> childExpressions(Expression expression) => switch (expression) {
      ParenthesizedExpression(:final expression) => [expression],
      PrefixExpression(:final operand) => [operand],
      BinaryExpression(:final leftOperand, :final rightOperand) => [leftOperand, rightOperand],
      ConditionalExpression(:final condition, :final thenExpression, :final elseExpression) => [
          condition,
          thenExpression,
          elseExpression,
        ],
      // A Computed's closure: its single expression is compiled, so every expression rule checks it.
      FunctionExpression() when isComputedClosure(expression) => [
          if (computedExpression(expression) case final body?) body,
        ],
      MethodInvocation(:final argumentList) || InstanceCreationExpression(:final argumentList) => [
          for (final argument in argumentList.arguments) argument.argumentExpression,
        ],
      _ => const [],
    };

/// Visits [root] and its supported subexpressions in source order. If [visit] returns false, the children of
/// that node are skipped (used after reporting a node, so each problem is reported once).
void walkExpression(Expression root, bool Function(Expression expression) visit) {
  if (!visit(root)) return;
  for (final child in childExpressions(root)) {
    walkExpression(child, visit);
  }
}

/// Every supported subexpression of [root], including [root], in source order.
Iterable<Expression> subexpressions(Expression root) sync* {
  yield root;
  for (final child in childExpressions(root)) {
    yield* subexpressions(child);
  }
}
