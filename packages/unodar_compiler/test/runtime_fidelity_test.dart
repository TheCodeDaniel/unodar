/// Runtime fidelity harness (docs/PLAN.md step 8): the runtime counterpart of the constexpr harnesses.
///
/// The constexpr harnesses prove what avr-gcc computes for **constant** inputs, but with constant inputs the AVR
/// core's LTO folds everything, and `static_assert` cannot see runtime values. These tests run real programs in the
/// avr8js ATmega328P simulator (`tool/avr_runner`) with inputs that only exist at runtime (the simulated ADC,
/// timers, and `volatile` globals) and read the PASS/FAIL lines they print on the serial port.
///
/// Every check has a negative control that must FAIL, so the harness is shown to be able to fail.
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';

import 'arduino_toolchain.dart';
import 'test_paths.dart';

/// The PASS/FAIL lines of [output], which must end with DONE.
List<String> results(String output) {
  expect(output, contains('DONE'), reason: 'the program did not finish:\n$output');
  return [
    for (final line in output.split(RegExp(r'\r?\n')))
      if (line.startsWith('PASS ') || line.startsWith('FAIL ')) line
  ];
}

void main() {
  final gate = simulatorGate();

  group('avr8js', () {
    group('32-bit wraparound across INT32_MAX/INT32_MIN (hand-written C++, volatile operands)', () {
      final source = File(fromPackage('test', 'runtime', 'wrap_boundary', 'wrap_boundary.ino')).readAsStringSync();

      test('built with -fwrapv, every check passes', () async {
        gate.check();
        final build = await compileSketch('wrap_boundary', source);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final lines = results(await runInSimulator(build.hexPath));
        expect(lines, hasLength(9));
        expect(lines.where((l) => l.startsWith('FAIL')), isEmpty, reason: lines.join('\n'));
        expect(lines, contains('PASS now - last >= interval across the wrap'));
      });

      test('negative control: built without -fwrapv, the comparisons GCC may fold print FAIL', () async {
        gate.check();
        final build = await compileSketch('wrap_boundary', source, buildProperties: const []);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final lines = results(await runInSimulator(build.hexPath));
        expect(lines, containsAll(['FAIL x + 1 > x is false for INT32_MAX', 'FAIL x - 1 < x is false for INT32_MIN']));
      });
    });

    group('Dart identities with runtime inputs (compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'runtime', 'identities', 'input.dart'));
        if (result is! CompileSuccess) fail('the fixture did not compile with unodar: $result');
        return result.cpp;
      }

      Future<List<String>> run(String cpp, Map<int, double> adc) async {
        final build = await compileSketch('identities', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return results(await runInSimulator(build.hexPath, adc: adc));
      }

      // A0 drives `level` (0..1023), A1 drives `offset` (-1000..23): extremes and values in between.
      for (final adc in [
        {0: 5.0, 1: 0.0},
        {0: 0.7, 1: 4.9},
        {0: 2.5, 1: 1.3},
      ]) {
        test('every identity holds with A0=${adc[0]} V, A1=${adc[1]} V', () async {
          gate.check();
          final lines = await run(await generated(), adc);
          expect(lines, hasLength(10));
          expect(lines.where((l) => l.startsWith('FAIL')), isEmpty, reason: lines.join('\n'));
        });
      }

      // Negative controls: the naive C++ translation of one construct each, which the emitter avoids.
      String naive(String cpp, String from, String to) {
        expect(cpp, contains(from), reason: 'the generated code changed; update the negative control');
        return cpp.replaceAll(from, to);
      }

      test('negative control: without the 32-bit widening, analogRead(A0) * 100 overflows 16 bits', () async {
        gate.check();
        final cpp = naive(await generated(), 'analogRead(A0) * 100L', 'analogRead(A0) * 100');
        expect(await run(cpp, {0: 5.0, 1: 0.0}), contains('FAIL analogRead(A0) * 100 is computed in 32 bits'));
      });

      test("negative control: C++'s % instead of unodar_mod is negative for negative values", () async {
        gate.check();
        final cpp = naive(await generated(), 'unodar_mod(offset, 7)', '(offset % 7)');
        expect(await run(cpp, {0: 5.0, 1: 0.0}), contains('FAIL % is never negative'));
      });
    });

    group('widget runtime (runtime/unodar_widgets.h, hand-written sketch)', () {
      final sketch = File(fromPackage('test', 'runtime', 'widgets', 'widgets.ino')).readAsStringSync();
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();

      Future<List<String>> run(String header) async {
        final build = await compileSketch('widgets', sketch, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return results(await runInSimulator(build.hexPath));
      }

      test('debounce, held at boot, Every count, drift, catch-up and the 2^32 wrap all pass', () async {
        gate.check();
        final lines = await run(header);
        expect(lines, hasLength(9));
        expect(lines.where((l) => l.startsWith('FAIL')), isEmpty, reason: lines.join('\n'));
      });

      // Negative controls: a plausible wrong implementation of one rule each, which the checks must catch.
      String broken(String from, String to) {
        expect(header, contains(from), reason: 'the runtime header changed; update the negative control');
        return header.replaceAll(from, to);
      }

      test('negative control: without debouncing, a bouncing press counts more than once', () async {
        gate.check();
        final lines = await run(broken('kDebounceMs = 50', 'kDebounceMs = 0'));
        expect(lines, contains('FAIL a bouncing press, a clean press and a glitch give exactly 2 presses'));
      });

      test('negative control: rescheduling from the time a tick was noticed drifts and skips catch-up', () async {
        gate.check();
        final lines = await run(broken('last_ += interval_;', 'last_ = now;'));
        expect(lines,
            containsAll(['FAIL Every is drift-free when polled late', 'FAIL missed ticks are caught up one per call']));
      });

      test('negative control: comparing deadlines instead of elapsed time breaks at the millis() wrap', () async {
        gate.check();
        final lines = await run(broken('now - last_ < interval_', 'now < last_ + interval_'));
        expect(lines, contains('FAIL Every ticks on schedule across the millis() wrap'));
        expect(lines.where((l) => l.startsWith('FAIL')), hasLength(1), reason: lines.join('\n'));
      });
    });

    test('examples/dial reports the potentiometer reading over Serial', () async {
      gate.check();
      final result = await Compiler().compile(fromPackage('..', '..', 'examples', 'dial', 'main.dart'));
      if (result is! CompileSuccess) fail('examples/dial did not compile with unodar: $result');
      final build = await compileSketch('dial', result.cpp);
      printOnFailure(build.rawOutput);
      expect(build.success, isTrue);
      // 2.5 V on A0 reads 512: the servo angle is 512 * 180 ~/ 1023 = 90, and 512 * 5.0 / 1023 prints as 2.502.
      final output = await runInSimulator(build.hexPath, adc: {0: 2.5}, until: 'volts=2.502');
      expect(output, startsWith('dial ready\r\n'));
      expect(output, contains('level=512 angle=90 volts=2.502'));
    });
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));
}
