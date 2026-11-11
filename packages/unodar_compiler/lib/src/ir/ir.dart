/// The unodar intermediate representation (PRD §9.5 step 3, §9.10 "IR is the seam").
///
/// Lowering produces IR from the analyzer AST; the emitter consumes only IR. The emitter must never see the AST, so
/// that every feature is added as new IR nodes plus their lowering and emission, independently testable on each
/// side.
///
/// Names in the IR are already **C++ names**: the Dart → C++ mapping happens once, during lowering, through the API
/// registry. Every declaration and statement carries the 1-based Dart source line it came from, which becomes a
/// `#line` directive.
///
/// Expressions are **typed** trees **without parentheses**: the tree is the grouping Dart parsed, and the emitter
/// decides where C++ needs parentheses. The IR states Dart semantics (`%` is Dart's non-negative modulo, `/` yields
/// a double); turning that into equivalent C++ (helpers, conversions, 32-bit widening) is the emitter's job.
library;

/// The value types of the Phase 2 subset (docs/SUBSET.md "Types"). The target maps them to C++ type names.
enum IrType {
  void_,
  bool_,

  /// Dart `int`.
  int32,

  /// Dart `double`.
  float32,
  uint8,
  uint16,
  int16;

  /// Whether this is one of the integer types (`int` or a sized type).
  bool get isInteger => this == int32 || isSized;

  /// `Uint8`, `Uint16`, or `Int16`.
  bool get isSized => this == uint8 || this == uint16 || this == int16;

  bool get isNumeric => isInteger || this == float32;
}

/// How a variable may change. Dart `const` / `final` / neither.
enum IrStorage {
  /// Dart `const`: a compile-time constant (C++ `constexpr`).
  constant,

  /// Dart `final`: assigned once (C++ `const`).
  final_,

  /// A normal, assignable variable.
  mutable,
}

/// A whole translation unit: one Dart source file → one sketch.
final class IrProgram {
  const IrProgram({required this.sourceName, this.globals = const [], required this.functions});

  /// Display name of the Dart source (basename), used in `#line` directives.
  final String sourceName;

  /// Top-level variables in source order. Their initializers are constant expressions.
  final List<IrGlobal> globals;

  /// Functions in source order.
  final List<IrFunction> functions;
}

final class IrGlobal {
  const IrGlobal({
    required this.name,
    required this.type,
    required this.storage,
    required this.initializer,
    required this.line,
  });

  final String name;
  final IrType type;
  final IrStorage storage;
  final IrExpression initializer;
  final int line;
}

final class IrParameter {
  const IrParameter(this.name, this.type);

  final String name;
  final IrType type;
}

/// A top-level function. [isEntryPoint] marks `setup`/`loop`, which Arduino declares itself (no prototype).
final class IrFunction {
  const IrFunction({
    required this.name,
    required this.line,
    required this.body,
    this.returnType = IrType.void_,
    this.parameters = const [],
    this.isEntryPoint = false,
  });

  final String name;
  final int line;
  final IrType returnType;
  final List<IrParameter> parameters;
  final List<IrStatement> body;
  final bool isEntryPoint;
}

// ---------------------------------------------------------------------------------------------------------------
// Statements

sealed class IrStatement {
  const IrStatement({required this.line});

  final int line;
}

/// An expression evaluated for its effect, in practice a call: `digitalWrite(13, HIGH);`, `pulse(300);`.
final class IrExpressionStatement extends IrStatement {
  const IrExpressionStatement(this.expression, {required super.line});

  final IrExpression expression;
}

/// A local variable. [initializer] is null for `int x;` (Dart's definite assignment guarantees a write before any
/// read).
final class IrLocal extends IrStatement {
  const IrLocal({
    required this.name,
    required this.type,
    required this.storage,
    this.initializer,
    required super.line,
  });

  final String name;
  final IrType type;
  final IrStorage storage;
  final IrExpression? initializer;
}

enum IrAssignOp {
  assign('='),
  add('+='),
  subtract('-=');

  const IrAssignOp(this.symbol);

  final String symbol;
}

/// `target = value;`, `target += value;`, `target -= value;`. Assignments are statements only (docs/SUBSET.md).
final class IrAssign extends IrStatement {
  const IrAssign(this.target, this.op, this.value, {required super.line});

  /// The variable assigned (a local, parameter, or global).
  final String target;
  final IrAssignOp op;
  final IrExpression value;
}

/// `target++;` or `target--;` (prefix and postfix are the same as statements).
final class IrIncrement extends IrStatement {
  const IrIncrement(this.target, {this.decrement = false, required super.line});

  final String target;
  final bool decrement;
}

/// `if (condition) { then } else { otherwise }`. An `else if` is an [otherwise] holding exactly one [IrIf].
final class IrIf extends IrStatement {
  const IrIf(this.condition, this.then, {this.otherwise, required super.line});

  final IrExpression condition;
  final List<IrStatement> then;
  final List<IrStatement>? otherwise;
}

final class IrWhile extends IrStatement {
  const IrWhile(this.condition, this.body, {required super.line});

  final IrExpression condition;
  final List<IrStatement> body;
}

/// A C-style `for`. [initializer] is an [IrLocal] or an assignment; [updates] are [IrAssign]/[IrIncrement].
final class IrFor extends IrStatement {
  const IrFor({
    this.initializer,
    this.condition,
    this.updates = const [],
    required this.body,
    required super.line,
  });

  final IrStatement? initializer;
  final IrExpression? condition;
  final List<IrStatement> updates;
  final List<IrStatement> body;
}

final class IrReturn extends IrStatement {
  const IrReturn(this.value, {required super.line});

  final IrExpression? value;
}

final class IrBreak extends IrStatement {
  const IrBreak({required super.line});
}

final class IrContinue extends IrStatement {
  const IrContinue({required super.line});
}

/// A nested `{ … }` block.
final class IrBlock extends IrStatement {
  const IrBlock(this.body, {required super.line});

  final List<IrStatement> body;
}

// ---------------------------------------------------------------------------------------------------------------
// Expressions

sealed class IrExpression {
  const IrExpression();

  /// The Dart static type of this expression.
  IrType get type;
}

final class IrIntLiteral extends IrExpression {
  const IrIntLiteral(this.value);

  final int value;

  @override
  IrType get type => IrType.int32;
}

final class IrDoubleLiteral extends IrExpression {
  const IrDoubleLiteral(this.value);

  final double value;

  @override
  IrType get type => IrType.float32;
}

final class IrBoolLiteral extends IrExpression {
  const IrBoolLiteral(this.value);

  final bool value;

  @override
  IrType get type => IrType.bool_;
}

/// A reference to a named C++ constant or macro from the API registry, such as `HIGH`.
final class IrConstant extends IrExpression {
  const IrConstant(this.name, {this.type = IrType.int32});

  /// The C++ name.
  final String name;

  @override
  final IrType type;
}

/// A reference to a user variable or parameter.
final class IrVariable extends IrExpression {
  const IrVariable(this.name, this.type);

  final String name;

  @override
  final IrType type;
}

/// A call to a C++ function (an API function or a user function), with positional arguments in C++ order.
final class IrCall extends IrExpression {
  const IrCall(this.function, this.arguments, {this.type = IrType.void_});

  /// The C++ function name.
  final String function;
  final List<IrExpression> arguments;

  @override
  final IrType type;
}

/// Binary operators with **Dart** semantics.
enum IrBinaryOp {
  add('+'),
  subtract('-'),
  multiply('*'),

  /// Dart `~/` on ints: truncates toward zero.
  truncatingDivide('~/'),

  /// Dart `%` on ints: the result is never negative.
  modulo('%'),

  /// Dart `/`: always a double result.
  divide('/'),
  equal('=='),
  notEqual('!='),
  less('<'),
  lessOrEqual('<='),
  greater('>'),
  greaterOrEqual('>='),
  and('&&'),
  or('||');

  const IrBinaryOp(this.dartSymbol);

  final String dartSymbol;

  bool get isComparison => index >= equal.index && index <= greaterOrEqual.index;
  bool get isLogical => this == and || this == or;
}

final class IrBinary extends IrExpression {
  const IrBinary(this.op, this.left, this.right, this.type);

  final IrBinaryOp op;
  final IrExpression left;
  final IrExpression right;

  @override
  final IrType type;
}

enum IrUnaryOp { negate, not }

final class IrUnary extends IrExpression {
  const IrUnary(this.op, this.operand, this.type);

  final IrUnaryOp op;
  final IrExpression operand;

  @override
  final IrType type;
}

/// `condition ? then : otherwise`.
final class IrConditional extends IrExpression {
  const IrConditional(this.condition, this.then, this.otherwise, this.type);

  final IrExpression condition;
  final IrExpression then;
  final IrExpression otherwise;

  @override
  final IrType type;
}

/// An explicit conversion: `Uint8(x)` (wrapping) or a widening the lowering asks for.
final class IrConvert extends IrExpression {
  const IrConvert(this.type, this.operand);

  @override
  final IrType type;
  final IrExpression operand;
}
