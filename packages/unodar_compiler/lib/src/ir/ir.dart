/// The unodar intermediate representation (PRD §9.5 step 3, §9.10 "IR is the seam").
///
/// Lowering produces IR from the analyzer AST; the emitter consumes only IR. The emitter must never see the AST, so
/// that every later feature (variables, widgets, signals) is added as new IR nodes plus their lowering and emission,
/// independently testable on each side.
///
/// Names in the IR are already **C++ names**: the Dart → C++ mapping happens once, during lowering, through the API
/// registry. Every node carries the 1-based Dart source line it came from, which becomes a `#line` directive.
library;

/// A whole translation unit: one Dart source file → one sketch.
final class IrProgram {
  const IrProgram({required this.sourceName, required this.functions});

  /// Display name of the Dart source (basename), used in `#line` directives.
  final String sourceName;

  /// Functions in source order.
  final List<IrFunction> functions;
}

/// A `void name()` function. Phase 1 has only `setup` and `loop`; parameters and return types arrive in Phase 2.
final class IrFunction {
  const IrFunction({required this.name, required this.line, required this.body});

  final String name;
  final int line;
  final List<IrStatement> body;
}

sealed class IrStatement {
  const IrStatement({required this.line});

  final int line;
}

/// A call to a C++ function as a statement, e.g. `digitalWrite(13, HIGH);`.
final class IrCall extends IrStatement {
  const IrCall(this.function, this.arguments, {required super.line});

  /// The C++ function name.
  final String function;
  final List<IrExpression> arguments;
}

sealed class IrExpression {
  const IrExpression();
}

final class IrIntLiteral extends IrExpression {
  const IrIntLiteral(this.value);

  final int value;
}

/// A reference to a named C++ constant or macro such as `HIGH`.
final class IrConstant extends IrExpression {
  const IrConstant(this.name);

  /// The C++ name.
  final String name;
}
