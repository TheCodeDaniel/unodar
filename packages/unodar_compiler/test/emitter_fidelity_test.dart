/// Emitter-level fidelity harness (docs/DECISIONS.md "fidelity rule").
///
/// Each vector pairs an IR expression with the value **Dart itself** computes for the same expression (the right
/// column is real Dart code, run by this test). The emitter turns every vector into a `constexpr` global, the test
/// appends `static_assert(name == dartValue)`, and avr-gcc (via arduino-cli, real AVR type widths, 16-bit `int`)
/// must accept the sketch. A wrong translation is a compile error naming the vector. Signed overflow inside a
/// constant expression is also a hard error in avr-gcc, so a missing 32-bit widening is caught too.
///
/// Phase 2 later adds a source-level harness (Dart `const` declarations through the whole compiler, with values
/// from the analyzer's constant evaluator); this one pins down the emitter on its own, at the IR seam.
@Tags(['arduino'])
library;

// The Dart column deliberately evaluates literal conditions such as `true || …`.
// ignore_for_file: dead_code

import 'package:test/test.dart';
import 'package:unodar/unodar.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';
import 'package:unodar_compiler/src/ir/ir.dart';

import 'arduino_toolchain.dart';
import 'ir_builders.dart';

typedef Vector = (String name, IrExpression ir, Object dart);

const t = IrBoolLiteral(true);
const f = IrBoolLiteral(false);
final u16max = v('u16max', IrType.uint16);
final u16one = v('u16one', IrType.uint16);
final u8a = v('u8a', IrType.uint8);
final i16min = v('i16min', IrType.int16);

/// INT32_MIN written as Dart requires it (`-2147483647 - 1`), since 2147483648 is not an int32 literal.
final int32Min = sub(neg(i(2147483647)), i(1));

/// Operands the vectors read, with their Dart values used on the right-hand side.
final operands = [
  IrGlobal(name: 'u16max', type: IrType.uint16, storage: IrStorage.constant, initializer: i(65535), line: 1),
  IrGlobal(name: 'u16one', type: IrType.uint16, storage: IrStorage.constant, initializer: i(1), line: 2),
  IrGlobal(name: 'u8a', type: IrType.uint8, storage: IrStorage.constant, initializer: i(200), line: 3),
  IrGlobal(name: 'i16min', type: IrType.int16, storage: IrStorage.constant, initializer: i(-32768), line: 4),
];
const Uint16 dU16max = Uint16(65535);
const Uint16 dU16one = Uint16(1);
const Uint8 dU8a = Uint8(200);
const Int16 dI16min = Int16(-32768);

final List<Vector> vectors = [
  // Dart % is never negative; C++ % keeps the sign of the left operand.
  ('mod_neg_pos', mod(i(-7), i(2)), -7 % 2),
  ('mod_pos_neg', mod(i(7), i(-2)), 7 % -2),
  ('mod_neg_neg', mod(i(-7), i(-2)), -7 % -2),
  ('mod_pos_pos', mod(i(7), i(2)), 7 % 2),
  ('mod_exact', mod(i(-6), i(3)), -6 % 3),
  ('mod_big', mod(neg(i(1)), i(2147483647)), -1 % 2147483647),
  ('mod_of_sum', mod(add(i(-3), i(-4)), i(5)), (-3 + -4) % 5),
  // b == INT32_MIN: the helper must not compute -b.
  ('mod_by_min_neg', mod(i(-5), int32Min), -5 % -2147483648),
  ('mod_by_min_pos', mod(i(5), int32Min), 5 % -2147483648),
  ('mod_min_by_min', mod(int32Min, int32Min), -2147483648 % -2147483648),
  ('mod_min_by_max', mod(int32Min, i(2147483647)), -2147483648 % 2147483647),
  // ~/ truncates toward zero in both.
  ('tdiv_neg_pos', tdiv(i(-7), i(2)), -7 ~/ 2),
  ('tdiv_pos_neg', tdiv(i(7), i(-2)), 7 ~/ -2),
  ('tdiv_neg_neg', tdiv(i(-7), i(-2)), -7 ~/ -2),
  ('tdiv_pos_pos', tdiv(i(7), i(2)), 7 ~/ 2),
  // / on ints yields a double (exactly representable values, so float == double here).
  ('div_int', div(i(7), i(2)), 7 / 2),
  ('div_neg', div(i(-7), i(2)), -7 / 2),
  ('div_quarter', div(i(1), i(4)), 1 / 4),
  ('div_neg_divisor', div(i(3), i(-8)), 3 / -8),
  // Precedence and associativity.
  ('prec_sub_right', sub(i(10), sub(i(4), i(3))), 10 - (4 - 3)),
  ('prec_sub_left', sub(sub(i(10), i(4)), i(3)), 10 - 4 - 3),
  ('prec_sum_times', mul(add(i(2), i(3)), i(4)), (2 + 3) * 4),
  ('prec_plus_product', add(i(2), mul(i(3), i(4))), 2 + 3 * 4),
  ('prec_neg_sum', neg(add(i(2), i(3))), -(2 + 3)),
  ('prec_neg_neg', neg(neg(i(5))), -(-5)),
  ('prec_minus_neg', sub(i(1), neg(i(5))), 1 - -5),
  ('prec_tdiv_right', tdiv(i(100), tdiv(i(20), i(3))), 100 ~/ (20 ~/ 3)),
  (
    'prec_ternary_else',
    cond(lt(i(1), i(2)), i(10), cond(gt(i(1), i(2)), i(20), i(30))),
    1 < 2 ? 10 : (1 > 2 ? 20 : 30)
  ),
  ('prec_ternary_sum', add(cond(eq(i(1), i(2)), i(1), i(2)), i(10)), (1 == 2 ? 1 : 2) + 10),
  ('logic_not_and', not(and(t, f)), !(true && false)),
  ('logic_or_and', or(f, and(t, f)), false || true && false),
  ('logic_and_or', and(or(t, f), f), (true || false) && false),
  ('logic_cmp_eq', eq(lt(i(2), i(1)), f), (2 < 1) == false),
  // 32-bit int arithmetic on a 16-bit-int board.
  ('wide_literals', mul(i(60), i(1000)), 60 * 1000),
  ('wide_chain', mul(mul(i(60), i(60)), i(1000)), 60 * 60 * 1000),
  ('wide_add_edge', add(i(32767), i(1)), 32767 + 1),
  ('wide_sub_edge', sub(neg(i(32767)), i(2)), -32767 - 2),
  ('wide_u16_sum', add(u16max, u16one), dU16max + dU16one),
  ('wide_u8_product', mul(u8a, u8a), dU8a * dU8a),
  ('wide_neg_i16', neg(i16min), -dI16min),
  ('wide_neg_u16', neg(u16one), -dU16one),
  ('wide_u16_lt_neg', lt(u16one, i(-1)), dU16one < -1),
  ('wide_u16_lt_negexpr', lt(u16one, neg(i(1))), dU16one < -(1)),
  ('wide_ternaries', mul(cond(t, i(60), i(30)), cond(t, i(1000), i(2000))), (true ? 60 : 30) * (true ? 1000 : 2000)),
  ('wide_macro', add(c('HIGH'), i(32767)), HIGH + 32767),
  // Sized conversions wrap identically.
  ('conv_u8', to(IrType.uint8, i(300)), Uint8(300)),
  ('conv_i16', to(IrType.int16, i(40000)), Int16(40000)),
  ('conv_u16', to(IrType.uint16, neg(i(1))), Uint16(-1)),
  ('conv_u8_sum', to(IrType.uint8, add(u8a, u8a)), Uint8(dU8a + dU8a)),
];

/// The sketch: operands, one `constexpr` per vector, and a `static_assert` per vector with Dart's value.
String fidelitySketch() {
  final program = IrProgram(
    sourceName: 'fidelity.dart',
    globals: [
      ...operands,
      for (final (index, (name, ir, _)) in vectors.indexed)
        IrGlobal(name: name, type: ir.type, storage: IrStorage.constant, initializer: ir, line: 10 + index),
    ],
    functions: [
      IrFunction(name: 'setup', line: 100, isEntryPoint: true, body: const []),
      IrFunction(name: 'loop', line: 101, isEntryPoint: true, body: const []),
    ],
  );
  final asserts = [
    for (final (name, _, dart) in vectors) 'static_assert($name == ${cppValue(dart)}, "$name: C++ differs from Dart");',
  ];
  // Assert k (1-based) sits on line k of the virtual file `fidelity_asserts`, so a failure names its vector.
  return '${const CppEmitter(UnoTarget()).emit(program)}\n// Dart values, computed by the test:\n'
      '#line 1 "fidelity_asserts"\n${asserts.join('\n')}\n';
}

String cppValue(Object value) => switch (value) {
      final int n => '${n}L',
      final double x => '${x}f',
      final bool b => '$b',
      _ => throw ArgumentError(value),
    };

void main() {
  final gate = arduinoGate();

  test('avr-gcc computes every vector exactly as Dart does', () async {
    gate.check();
    final sketch = fidelitySketch();
    final result = await compileSketch('fidelity', sketch);
    printOnFailure(sketch);
    printOnFailure(result.rawOutput);
    expect(result.success, isTrue, reason: 'a static_assert failed: the generated C++ differs from Dart');
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));

  // Negative controls: the harness must be able to fail. Each one puts back the naive C translation that unodar
  // avoids, and avr-gcc must then reject the sketch at exactly the named vector.
  final naive = <String, (String vector, String correct, String wrong)>{
    'C++ % instead of unodar_mod': ('mod_neg_pos', 'mod_neg_pos = unodar_mod(-7, 2);', 'mod_neg_pos = -7 % 2;'),
    'int arithmetic without 32-bit widening': (
      'wide_u8_product',
      'wide_u8_product = int32_t(u8a) * u8a;',
      'wide_u8_product = u8a * u8a;',
    ),
    'C++ / on ints instead of float division': ('div_int', 'div_int = float(7) / float(2);', 'div_int = 7 / 2;'),
    'unsigned comparison of a Uint16 with -1': (
      'wide_u16_lt_neg',
      'wide_u16_lt_neg = u16one < -1L;',
      'wide_u16_lt_neg = u16one < -1;',
    ),
    // The first draft of the helper added |b| as `(b < 0 ? -b : b)`, which overflows for b == INT32_MIN.
    'a % helper that negates b': (
      'mod_by_min_neg',
      CppEmitter.modHelper[1],
      'constexpr int32_t unodar_mod(int32_t a, int32_t b) { return a % b < 0 ? a % b + (b < 0 ? -b : b) : a % b; }',
    ),
  };
  for (final MapEntry(key: what, value: (vector, correct, wrong)) in naive.entries) {
    test('negative control: $what is detected', () async {
      gate.check();
      final sketch = fidelitySketch();
      expect(sketch, contains(correct), reason: 'the control must replace text the emitter really produces');
      final result = await compileSketch('fidelity', sketch.replaceFirst(correct, wrong));
      printOnFailure(result.rawOutput);
      expect(result.success, isFalse);
      // The error must point at this vector: its initializer line or its static_assert line.
      final index = vectors.indexWhere((v) => v.$1 == vector);
      expect(index, isNonNegative);
      expect(
        result.rawOutput,
        anyOf(contains('fidelity_asserts:${index + 1}:'), contains('fidelity.dart:${10 + index}:')),
        reason: 'avr-gcc must reject vector $vector, not something else',
      );
    }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));
  }
}
