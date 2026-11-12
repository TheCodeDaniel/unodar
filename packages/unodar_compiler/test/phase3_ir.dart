/// Hand-built IR for the Phase 3 nodes, written as lowering will produce it (docs/SUBSET.md): shared by
/// `emitter_test` (exact text) and `emitter_compile_test` (avr-gcc accepts it).
library;

import 'package:unodar_compiler/src/ir/ir.dart';

import 'ir_builders.dart';

/// `analogRead(pin)`: C++ returns a 16-bit `int`.
IrCall analogRead(IrExpression pin) =>
    IrCall('analogRead', [pin], type: IrType.int32, cppResult: const IrCppResult('int'));

/// `millis()`: C++ returns `unsigned long`.
const millis = IrCall('millis', [], type: IrType.int32, cppResult: IrCppResult('unsigned long'));

IrCall method(String receiver, String name, List<IrExpression> arguments,
        {IrType type = IrType.void_, IrCppResult? cppResult, List<String>? parameterCppTypes}) =>
    IrCall(name, arguments, receiver: receiver, type: type, cppResult: cppResult, parameterCppTypes: parameterCppTypes);

IrExpressionStatement statement(IrExpression expression, int line) => IrExpressionStatement(expression, line: line);

/// `b ? F("true") : F("false")`, which lowering produces for `Serial.print` of a `bool`.
IrConditional printableBool(IrExpression value) =>
    IrConditional(value, const IrStringLiteral('true'), const IrStringLiteral('false'), IrType.string);

/// A sketch with every Phase 3 node except Servo, which is not installed with the core (docs/PLAN.md step 6).
/// [extraIncludes] and [extraGlobals] add the Servo part for the unit test.
IrProgram phase3Program({List<String> extraIncludes = const [], List<IrGlobalDeclaration> extraGlobals = const []}) =>
    IrProgram(
      sourceName: 'phase3.dart',
      includes: ['Wire.h', 'SoftwareSerial.h', ...extraIncludes, 'Wire.h'],
      globals: [
        const IrBoundObject(
            name: 'link', cppClass: 'SoftwareSerial', arguments: [IrIntLiteral(10), IrIntLiteral(11)], line: 3),
        IrGlobal(name: 'last', type: IrType.int32, storage: IrStorage.mutable, initializer: i(0), line: 4),
        ...extraGlobals,
      ],
      functions: [
        IrFunction(name: 'setup', line: 6, isEntryPoint: true, body: [
          statement(method('Serial', 'begin', [i(9600)]), 7),
          statement(method('Wire', 'begin', []), 8),
          statement(method('link', 'begin', [i(4800)], parameterCppTypes: ['long']), 9),
        ]),
        IrFunction(name: 'loop', line: 11, isEntryPoint: true, body: [
          // final level = analogRead(A0) * 100;
          IrLocal(
              name: 'level',
              type: IrType.int32,
              storage: IrStorage.final_,
              initializer: mul(analogRead(c('A0')), i(100)),
              line: 12),
          // final now = millis();
          const IrLocal(name: 'now', type: IrType.int32, storage: IrStorage.final_, initializer: millis, line: 13),
          // if (now - last >= 1000) { … }
          IrIf(
              ge(sub(v('now'), v('last')), i(1000)),
              [
                IrAssign('last', IrAssignOp.assign, v('now'), line: 15),
                // Serial.println(level > 5000);
                statement(method('Serial', 'println', [printableBool(gt(v('level'), i(5000)))]), 16),
                // Serial.println(level / 7, digits: 3);
                statement(method('Serial', 'println', [div(v('level'), i(7)), i(3)]), 17),
                // Serial.print('tab\t"quoted" ??= é\n');
                statement(method('Serial', 'print', [const IrStringLiteral('tab\t"quoted" ??= é\n')]), 18),
                // Wire.write(level ~/ 100);  (uint8_t parameter, int argument)
                statement(
                    method('Wire', 'write', [tdiv(v('level'), i(100))],
                        type: IrType.int32, cppResult: const IrCppResult('size_t'), parameterCppTypes: ['uint8_t']),
                    19),
                // if (Wire.available() > 0) last += Wire.read();  (int results)
                IrIf(
                    gt(method('Wire', 'available', [], type: IrType.int32, cppResult: const IrCppResult('int')), i(0)),
                    [
                      IrAssign('last', IrAssignOp.add,
                          method('Wire', 'read', [], type: IrType.int32, cppResult: const IrCppResult('int')),
                          line: 21),
                    ],
                    line: 20),
                // final sent = link.write(Uint8(level));  (an int result without @CppType)
                IrLocal(
                    name: 'sent',
                    type: IrType.int32,
                    storage: IrStorage.final_,
                    initializer: method('link', 'write', [to(IrType.uint8, v('level'))],
                        type: IrType.int32, cppResult: const IrCppResult.unknown(), parameterCppTypes: ['uint8_t']),
                    line: 22),
                statement(method('Serial', 'println', [mul(v('sent'), i(2))]), 23),
                // cpp('noInterrupts();\ninterrupts();');
                const IrRawCpp('noInterrupts();\ninterrupts();', line: 24),
              ],
              line: 14),
        ]),
      ],
    );
