/// Terse IR constructors for emitter tests and the fidelity harness. Types follow Dart's static typing: integer
/// arithmetic (including on sized values) is `int`, `/` is `double`.
library;

import 'package:unodar_compiler/src/ir/ir.dart';

IrIntLiteral i(int value) => IrIntLiteral(value);
IrConstant c(String name) => IrConstant(name);
IrVariable v(String name, [IrType type = IrType.int32]) => IrVariable(name, type);
IrVariable b(String name) => IrVariable(name, IrType.bool_);
IrVariable d(String name) => IrVariable(name, IrType.float32);

IrExpressionStatement call(String function, List<IrExpression> arguments, {required int line}) =>
    IrExpressionStatement(IrCall(function, arguments), line: line);

IrType _numeric(IrExpression l, IrExpression r) =>
    l.type == IrType.float32 || r.type == IrType.float32 ? IrType.float32 : IrType.int32;

IrBinary add(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.add, l, r, _numeric(l, r));
IrBinary sub(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.subtract, l, r, _numeric(l, r));
IrBinary mul(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.multiply, l, r, _numeric(l, r));
IrBinary mulD(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.multiply, l, r, IrType.float32);
IrBinary tdiv(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.truncatingDivide, l, r, IrType.int32);
IrBinary mod(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.modulo, l, r, IrType.int32);
IrBinary div(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.divide, l, r, IrType.float32);
IrBinary eq(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.equal, l, r, IrType.bool_);
IrBinary ne(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.notEqual, l, r, IrType.bool_);
IrBinary lt(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.less, l, r, IrType.bool_);
IrBinary le(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.lessOrEqual, l, r, IrType.bool_);
IrBinary gt(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.greater, l, r, IrType.bool_);
IrBinary ge(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.greaterOrEqual, l, r, IrType.bool_);
IrBinary and(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.and, l, r, IrType.bool_);
IrBinary or(IrExpression l, IrExpression r) => IrBinary(IrBinaryOp.or, l, r, IrType.bool_);
IrUnary neg(IrExpression e) => IrUnary(IrUnaryOp.negate, e, e.type == IrType.float32 ? IrType.float32 : IrType.int32);
IrUnary not(IrExpression e) => IrUnary(IrUnaryOp.not, e, IrType.bool_);
IrConditional cond(IrExpression p, IrExpression t, IrExpression o) => IrConditional(p, t, o, t.type);
IrConditional condB(IrExpression p, IrExpression t, IrExpression o) => IrConditional(p, t, o, IrType.bool_);
IrConvert to(IrType type, IrExpression e) => IrConvert(type, e);
