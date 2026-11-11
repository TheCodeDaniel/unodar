/// Source-level fidelity harness (plan step 6; the emitter-level one is emitter_fidelity_test.dart).
///
/// `test/fidelity/vectors.dart` is an ordinary unodar program whose top-level `const` declarations are test
/// vectors. The **expected** value of each comes from Dart itself: the analyzer's constant evaluator, which
/// implements the language specification. The **actual** value comes from the whole unodar pipeline (frontend,
/// validator, lowering, emitter): the generated sketch is compiled by avr-gcc with a
/// `static_assert(name == dartValue)` per vector. A disagreement anywhere in the pipeline fails the build at that
/// vector, on real AVR type widths.
@Tags(['arduino'])
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';
import 'package:unodar_compiler/src/frontend/frontend.dart';

import 'arduino_toolchain.dart';
import 'test_paths.dart';

final fixture = fromPackage('test', 'fidelity', 'vectors.dart');

/// Every `const` in the fixture with Dart's value for it, in source order.
Future<List<(String, Object)>> dartValues() async {
  final result = await const Frontend().resolve(fixture);
  if (result is! FrontendSuccess) fail('could not analyze the fixture: $result');
  return [
    for (final declaration in result.source.unit.declarations.whereType<TopLevelVariableDeclaration>())
      for (final variable in declaration.variables.variables)
        if (variable.isConst) (variable.name.lexeme, _value(variable)),
  ];
}

Object _value(VariableDeclaration variable) {
  final object = variable.declaredFragment!.element.computeConstantValue();
  return object?.toIntValue() ??
      object?.toDoubleValue() ??
      object?.toBoolValue() ??
      (throw StateError('no constant value for ${variable.name.lexeme}'));
}

String cppValue(Object value) => switch (value) {
      final int n => '${n}L',
      final double x => '${x}f',
      final bool b => '$b',
      _ => throw ArgumentError(value),
    };

/// The unodar output for the fixture plus one `static_assert` per vector, on its own `#line` file so that a
/// failure names the vector's line.
Future<String> sketch(List<(String, Object)> values) async {
  final result = await Compiler().compile(fixture);
  if (result is! CompileSuccess) fail('the fixture does not compile with unodar: $result');
  final asserts = [
    for (final (name, value) in values) 'static_assert($name == ${cppValue(value)}, "$name: C++ differs from Dart");',
  ];
  return '${result.cpp}\n// Dart values, from the analyzer:\n#line 1 "fidelity_asserts"\n${asserts.join('\n')}\n';
}

void main() {
  final gate = arduinoGate();

  test('the fixture covers every Phase 2 operator family', () async {
    final names = (await dartValues()).map((v) => v.$1).toList();
    expect(names.length, greaterThanOrEqualTo(45));
    for (final prefix in ['mod', 'div', 'slash', 'prec', 'logic', 'compare', 'wide', 'conv', 'double', 'float']) {
      expect(names.where((n) => n.startsWith(prefix)), isNotEmpty, reason: 'no $prefix… vector');
    }
  });

  test('avr-gcc computes every vector exactly as Dart does', () async {
    gate.check();
    final values = await dartValues();
    final cpp = await sketch(values);
    final build = await compileSketch('fidelity_source', cpp);
    printOnFailure(cpp);
    printOnFailure(build.rawOutput);
    expect(build.success, isTrue, reason: 'a static_assert failed: the compiled C++ differs from Dart');
    print('source-level fidelity: ${values.length} vectors agree with Dart on arduino:avr:uno');
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));

  test('negative control: a C-style % in the same sketch is caught at its vector', () async {
    gate.check();
    final values = await dartValues();
    final cpp = await sketch(values);
    const correct = 'modNegPos = unodar_mod(-7, 2);';
    expect(cpp, contains(correct));
    final build = await compileSketch('fidelity_source', cpp.replaceFirst(correct, 'modNegPos = -7 % 2;'));
    final index = values.indexWhere((v) => v.$1 == 'modNegPos');
    expect(build.success, isFalse);
    expect(build.rawOutput, contains('fidelity_asserts:${index + 1}:'));
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));
}
