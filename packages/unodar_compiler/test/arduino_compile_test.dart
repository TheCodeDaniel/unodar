/// Checks against the real Arduino toolchain (PRD §9.8 compile check, PRD §11 size budgets).
///
/// Requires `arduino-cli` on PATH and the `arduino:avr` core installed; see `arduino_toolchain.dart` for how a
/// missing toolchain is reported (skipped with install instructions, never silently).
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
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

/// Every golden case that compiles (has an expected.ino), in name order. Each one must build for the Uno and have
/// a size budget: CLAUDE.md requires an arduino-cli compile check and a budget for every positive golden.
List<String> positiveGoldens() {
  final root = Directory(fromPackage('test', 'golden'));
  return [
    for (final dir in root.listSync().whereType<Directory>())
      if (File(p.join(dir.path, 'expected.ino')).existsSync()) p.basename(dir.path),
  ]..sort();
}

void main() {
  final gate = arduinoGate();
  final checkToolchain = gate.check;
  final goldens = positiveGoldens();

  test('every positive golden has a size budget, and every budget a positive golden', () {
    expect(goldens.where((g) => !sizeBudgets.containsKey(g)), isEmpty,
        reason: 'add a SizeBudget in test/size_budgets.dart (dedicated commit, with the measurement)');
    expect(sizeBudgets.keys.where((k) => !goldens.contains(k)), isEmpty, reason: 'remove budgets of deleted goldens');
  });

  group('arduino:avr:uno', () {
    // One arduino-cli build per case, shared by the compile and budget tests (a build takes seconds).
    final builds = <String, Future<ArduinoBuild>>{};
    Future<ArduinoBuild> build(String goldenCase) => builds.putIfAbsent(goldenCase, () => buildGolden(goldenCase));

    for (final goldenCase in goldens) {
      test('$goldenCase compiles and stays within its size budget', () async {
        checkToolchain();
        final result = await build(goldenCase);
        printOnFailure(result.rawOutput);
        expect(result.success, isTrue, reason: 'arduino-cli compile failed');

        final flash = result.section('text');
        final ram = result.section('data');
        final budget = sizeBudgets[goldenCase];
        if (budget == null) fail('$goldenCase: flash $flash B, RAM $ram B, but it has no size budget');
        print(
          '$goldenCase: flash $flash B (baseline ${budget.baselineFlash}, max ${budget.maxFlash}), '
          'RAM $ram B (baseline ${budget.baselineRam}, max ${budget.maxRam})',
        );
        const policy = 'See test/size_budgets.dart: find the cause before changing a budget.';
        expect(flash, lessThanOrEqualTo(budget.maxFlash), reason: '$goldenCase flash over budget. $policy');
        expect(ram, lessThanOrEqualTo(budget.maxRam), reason: '$goldenCase RAM over budget. $policy');
      });
    }

    for (final example in ['blink', 'pulse']) {
      test('examples/$example builds for the Uno', () async {
        checkToolchain();
        final result = await Compiler().compile(fromPackage('..', '..', 'examples', example, 'main.dart'));
        if (result is! CompileSuccess) fail('examples/$example did not compile with unodar: $result');
        final build = await compileSketch(example, result.cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue, reason: 'arduino-cli compile failed');
      });
    }
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));
}
