/// Checks against the real Arduino toolchain (PRD §9.8 compile check, PRD §11 size budgets).
///
/// Requires `arduino-cli` on PATH and the `arduino:avr` core installed; see `arduino_toolchain.dart` for how a
/// missing toolchain is reported (skipped with install instructions, never silently).
@Tags(['arduino'])
library;

import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';

import 'arduino_toolchain.dart';
import 'size_budgets.dart';
import 'test_paths.dart';

/// Compiles `test/golden/<goldenCase>` with unodar, then with arduino-cli for the Uno.
Future<ArduinoBuild> buildGolden(String goldenCase) async {
  final result = await Compiler().compile(fromPackage('test', 'golden', goldenCase, 'input.dart'));
  if (result is! CompileSuccess) fail('$goldenCase did not compile with unodar: $result');
  return compileSketch(goldenCase, result.cpp);
}

void main() {
  final gate = arduinoGate();
  final checkToolchain = gate.check;

  group('arduino:avr:uno', () {
    // One arduino-cli build per case, shared by the compile and budget tests (a build takes seconds).
    final builds = <String, Future<ArduinoBuild>>{};
    Future<ArduinoBuild> build(String goldenCase) => builds.putIfAbsent(goldenCase, () => buildGolden(goldenCase));

    test('generated blink sketch compiles', () async {
      checkToolchain();
      final result = await build('blink');
      printOnFailure(result.rawOutput);
      expect(result.success, isTrue, reason: 'arduino-cli compile failed');
    });

    for (final MapEntry(key: goldenCase, value: budget) in sizeBudgets.entries) {
      test('$goldenCase stays within its size budget', () async {
        checkToolchain();
        final result = await build(goldenCase);
        printOnFailure(result.rawOutput);
        expect(result.success, isTrue, reason: 'arduino-cli compile failed');

        final flash = result.section('text');
        final ram = result.section('data');
        print(
          '$goldenCase: flash $flash B (baseline ${budget.baselineFlash}, max ${budget.maxFlash}), '
          'RAM $ram B (baseline ${budget.baselineRam}, max ${budget.maxRam})',
        );
        const policy = 'See test/size_budgets.dart: find the cause before changing a budget.';
        expect(flash, lessThanOrEqualTo(budget.maxFlash), reason: '$goldenCase flash over budget. $policy');
        expect(ram, lessThanOrEqualTo(budget.maxRam), reason: '$goldenCase RAM over budget. $policy');
      });
    }
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));
}
