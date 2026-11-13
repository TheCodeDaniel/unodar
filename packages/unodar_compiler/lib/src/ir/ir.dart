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

/// The value types of the subset (docs/SUBSET.md "Types"). The target maps them to C++ type names.
enum IrType {
  void_,
  bool_,

  /// A string literal. Only an argument of `Serial.print`/`println` (C++ `F("…")`, a flash string); never the
  /// type of a variable.
  string,

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
  const IrProgram({
    required this.sourceName,
    this.includes = const [],
    this.localIncludes = const [],
    this.globals = const [],
    required this.functions,
  });

  /// Display name of the Dart source (basename), used in `#line` directives.
  final String sourceName;

  /// Headers the program needs beyond the target's (`Servo.h` for a used binding, `@CppInclude` headers), in
  /// order. Emitted as `#include <…>` after the target's includes, each once.
  final List<String> includes;

  /// Sketch-local headers, i.e. files written next to the `.ino` (`unodar_widgets.h` for a widget program), in
  /// order. Emitted as `#include "…"` after [includes], each once.
  final List<String> localIncludes;

  /// Top-level variables and bound objects, in source order.
  final List<IrGlobalDeclaration> globals;

  /// Functions in source order.
  final List<IrFunction> functions;
}

sealed class IrGlobalDeclaration {
  const IrGlobalDeclaration({required this.name, required this.line});

  final String name;
  final int line;
}

/// A top-level variable. Its initializer is a constant expression.
final class IrGlobal extends IrGlobalDeclaration {
  const IrGlobal({
    required super.name,
    required this.type,
    required this.storage,
    required this.initializer,
    required super.line,
  });

  final IrType type;
  final IrStorage storage;
  final IrExpression initializer;
}

/// A statically allocated object of a bound C++ class: `Servo servo;`, `SoftwareSerial link(10, 11);`. Its
/// constructor arguments are constant expressions, in C++ parameter order.
final class IrBoundObject extends IrGlobalDeclaration {
  const IrBoundObject({required super.name, required this.cppClass, this.arguments = const [], required super.line});

  /// The C++ class name, possibly qualified (`ns::Name`).
  final String cppClass;
  final List<IrExpression> arguments;
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

/// Raw C++ from `cpp('…')`, emitted verbatim (one line of output per line of [code]).
final class IrRawCpp extends IrStatement {
  const IrRawCpp(this.code, {required super.line});

  final String code;
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

/// A string literal, [value] being the string Dart denotes (escapes resolved). C++ `F("…")`.
final class IrStringLiteral extends IrExpression {
  const IrStringLiteral(this.value);

  final String value;

  @override
  IrType get type => IrType.string;
}

/// A call to a C++ function (an API function or a user function) or, with a [receiver], to a method of a C++
/// object (`Serial.begin(9600)`, `servo.attach(9, 544, 2400)`). Arguments are positional, in C++ order, with
/// omitted named arguments already filled in with their defaults.
final class IrCall extends IrExpression {
  const IrCall(
    this.function,
    this.arguments, {
    this.type = IrType.void_,
    this.receiver,
    this.cppResult,
    this.parameterCppTypes,
  });

  /// The C++ function or method name.
  final String function;
  final List<IrExpression> arguments;

  /// The Dart result type.
  @override
  final IrType type;

  /// The C++ object a method is called on, or null for a function call.
  final String? receiver;

  /// The C++ result type, for API and binding calls whose C++ result may differ from the target's type for [type]
  /// (`analogRead` returns a 16-bit `int`, `millis` an `unsigned long`). Null when the C++ result is exactly the
  /// target's type for [type], as for user functions and `void` calls.
  final IrCppResult? cppResult;

  /// The exact C++ type of each parameter (`@CppType`), one per argument, to which the emitter converts arguments
  /// of another C++ type explicitly (`uint8_t(x)`), which also selects the right C++ overload. Null for calls whose
  /// arguments are passed as they are (user functions, the Arduino core functions).
  final List<String>? parameterCppTypes;
}

/// The C++ type an API or binding call returns (see [IrCall.cppResult]).
final class IrCppResult {
  const IrCppResult(String this.cppType);

  /// A binding method returning `int` without `@CppType`: the C++ type is not known, so the emitter always
  /// converts the result to 32 bits.
  const IrCppResult.unknown() : cppType = null;

  final String? cppType;
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
