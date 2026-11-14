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

import 'package:path/path.dart' as p;
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

    group('runner pin I/O (hand-written sketch)', () {
      late String hex;
      setUpAll(() async {
        if (gate.skip != false) return;
        final build =
            await compileSketch('pins', File(fromPackage('test', 'runtime', 'pins', 'pins.ino')).readAsStringSync());
        expect(build.success, isTrue, reason: build.rawOutput);
        // The build folder is removed by the tearDown of setUpAll, so keep the image.
        hex = File(build.hexPath).readAsStringSync();
      });

      Future<({String serial, List<String> pinLog})> run(List<String> pins) async {
        final file = File(p.join(Directory.systemTemp.createTempSync('unodar_hex_').path, 'pins.hex'))
          ..writeAsStringSync(hex);
        addTearDown(() => file.parent.deleteSync(recursive: true));
        return simulate(file.path, pins: pins);
      }

      /// The simulated time in ms of each `<pin> <state>` change in [log].
      List<double> changes(List<String> log, String pin, String state) => [
            for (final line in log)
              if (line.endsWith(' $pin $state')) double.parse(line.split(' ').first)
          ];

      test('an undriven pin reads HIGH with the pull-up and LOW without; a driven pin reads its level', () async {
        gate.check();
        final result = await run(['D3=high@50']);
        expect(result.serial, startsWith('boot D2=1 D3=0 A1=0\r\nD2=1 at 0\r\n'));
        expect(result.serial, contains('end D3=1 A1=0\r\nDONE'));
        expect(changes(result.pinLog, 'D2', 'input-pullup'), hasLength(1));
        expect(changes(result.pinLog, 'D13', 'low'), hasLength(1), reason: 'pinMode(13, OUTPUT) with PORT low');
      });

      test('a scheduled press and release reach the program and the output log at the scheduled time', () async {
        gate.check();
        final result = await run(['D2=low@100', 'D2=open@200']);
        final reports = RegExp(r'D2=(\d) at (\d+)').allMatches(result.serial).map((m) => (m[1], int.parse(m[2]!)));
        expect([for (final (level, _) in reports) level], ['1', '0', '1']);
        // millis() counts whole 1.024 ms timer overflows, so it can trail the simulated time by up to a millisecond
        // (and steps by 2 now and then): allow one millisecond either way.
        expect([for (final (_, ms) in reports) ms], [0, inInclusiveRange(99, 101), inInclusiveRange(199, 201)]);
        final high = changes(result.pinLog, 'D13', 'high');
        final low = changes(result.pinLog, 'D13', 'low');
        expect(high, [lessThan(1), allOf(greaterThanOrEqualTo(200), lessThan(200.1))]);
        expect(low, [lessThan(1), allOf(greaterThanOrEqualTo(100), lessThan(100.1))]);
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

      test('debounce, held at boot, Every count, drift, catch-up, the 2^32 wrap and the pins all pass', () async {
        gate.check();
        final lines = await run(header);
        expect(lines, hasLength(11));
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

    group('signal runtime (unodar::Signal<T> in runtime/unodar_widgets.h, hand-written sketch)', () {
      final sketch = File(fromPackage('test', 'runtime', 'signals', 'signals.ino')).readAsStringSync();
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();

      Future<List<String>> run({String? headerText, String? sketchText}) async {
        final build =
            await compileSketch('signals', sketchText ?? sketch, files: {'unodar_widgets.h': headerText ?? header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return results(await runInSimulator(build.hexPath));
      }

      String replaced(String text, String from, String to) {
        expect(text, contains(from), reason: 'the source changed; update the negative control');
        return text.replaceAll(from, to);
      }

      test('marks, equality (NaN, -0.0), coalescing, sized ranges and two-phase delivery all pass', () async {
        gate.check();
        final lines = await run();
        expect(lines, hasLength(10));
        expect(lines.where((l) => l.startsWith('FAIL')), isEmpty, reason: lines.join('\n'));
      });

      test('negative control: set() without the comparison marks equal writes', () async {
        gate.check();
        final lines = await run(headerText: replaced(header, 'if (value != value_) {', 'if (true) {'));
        expect(
            lines,
            containsAll([
              'FAIL an equal write does not mark the signal',
              'FAIL writing -0.0 onto 0.0 does not mark and keeps 0.0 (equal, as in Dart)',
            ]));
      });

      test('negative control: take() that does not clear the mark reports a change again', () async {
        gate.check();
        final lines = await run(
            headerText: replaced(header, '    changed_ = false;\n    return changed;', '    return changed;'));
        expect(lines, contains('FAIL a signal starts changed, and take() clears the mark'));
      });

      test('negative control: delivery without the snapshot delivers a write made during delivery at once', () async {
        gate.check();
        final lines = await run(sketchText: replaced(sketch, '#define NAIVE_DELIVERY 0', '#define NAIVE_DELIVERY 1'));
        expect(
            lines,
            contains(
                'FAIL a write made during delivery is delivered in the next pass, whatever the declaration order'));
      });
    });

    group('signal state: a Button writes signals, an Every reads them (golden signal_state, compiled by unodar)', () {
      final source = fromPackage('test', 'golden', 'signal_state', 'input.dart');
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      // Press 1 stable from 300 ms (bouncing first), press 2 from 1200 ms; Every(1 s) prints at 1000 and 2000 ms.
      const inputs = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];
      const cycles = 2100 * 16000; // 2.1 s at 16 MHz

      Future<String> generated() async {
        final result = await Compiler().compile(source);
        if (result is! CompileSuccess) fail('signal_state did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('signal_state', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: inputs, until: null, cycles: cycles)).serial;
      }

      test('every write form, sized wraparound and a 32-bit Int16 product print exactly as in Dart', () async {
        gate.check();
        // Press 1: count 0 + 1 + 10 - 5 - 1 = 5, ratio 1.0, lit true, level Uint8(253), depth Int16(-33000) = 32536.
        // Press 2: count 10, ratio 2.0, lit false, level Uint8(256) = 0, depth Int16(29536). depth * 1000 is 32-bit.
        expect(
            await run(await generated()),
            'count=5 ratio=1.00 lit=true level=253 depth=32536000\r\n'
            'count=10 ratio=2.00 lit=false level=0 depth=29536000\r\n');
      });

      test('negative control: the Int16 read without the 32-bit widening overflows in 16 bits', () async {
        gate.check();
        final cpp = await generated();
        expect(cpp, contains('depth.value() * 1000L'), reason: 'the generated code changed; update the control');
        final serial = await run(cpp.replaceAll('depth.value() * 1000L', 'depth.value() * 1000'));
        expect(serial, isNot(contains('depth=32536000')), reason: serial);
        expect(serial, contains('count=5 ratio=1.00 lit=true level=253 depth='), reason: serial);
      });
    });

    group('Watch delivery (goldens watch and watch_order, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();

      Future<String> generated(String golden) async {
        final result = await Compiler().compile(fromPackage('test', 'golden', golden, 'input.dart'));
        if (result is! CompileSuccess) fail('$golden did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String name, String cpp, List<String> pins, int ms, {String? headerText}) async {
        final build = await compileSketch(name, cpp, files: {'unodar_widgets.h': headerText ?? header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: pins, until: null, cycles: ms * 16000)).serial;
      }

      // watch: plus (D2) writes count twice, clear (D3) writes 0. Presses stable from 300, 800, 1300, 1800 ms.
      const presses = [
        'D2=low@300', 'D2=open@302', 'D2=low@304', 'D2=open@500', // plus (bouncing)
        'D3=low@800', 'D3=open@1000', // clear: 2 -> 0
        'D3=low@1300', 'D3=open@1500', // clear at 0: an equal write
        'D2=low@1800', 'D2=open@2000', // plus
      ];
      const watchTranscript = 'count 0\r\ntwice 0\r\n' // the initial value, once, at the end of setup()
          'count 2\r\ntwice 4\r\n' // two writes in one callback: one delivery, the last value
          'count 0\r\ntwice 0\r\n' // clear
          'count 2\r\ntwice 4\r\n'; // the second clear wrote an equal value: nothing

      test('initial value once, two writes delivered once, an equal write silent, Watches in children order', () async {
        gate.check();
        expect(await run('watch', await generated('watch'), presses, 2200), watchTranscript);
      });

      test('negative control: with set() marking equal writes, the clear at 0 is delivered', () async {
        gate.check();
        expect(header, contains('if (value != value_) {'));
        final serial = await run('watch', await generated('watch'), presses, 2200,
            headerText: header.replaceAll('if (value != value_) {', 'if (true) {'));
        expect(serial, isNot(watchTranscript));
        expect(serial, contains('count 0\r\ntwice 0\r\ncount 0\r\ntwice 0\r\n'), reason: serial);
      });

      // watch_order: the Watch of `a` writes `b`; `b` is declared between `a` and `d`.
      const orderTranscript = 'a2 0\r\na 0\r\nb 0\r\nd 0\r\n' // setup delivery: all start changed
          'b 10\r\n' // the write made during it, in the first loop() pass
          'a2 1\r\na 1\r\nd 1\r\n' // the press writes a and d: one pass
          'b 11\r\n'; // the Watch of a wrote b: the next pass

      test('flags and values are taken first: a write made during delivery arrives in the next pass, after d',
          () async {
        gate.check();
        expect(await run('watch_order', await generated('watch_order'), ['D2=low@300', 'D2=open@500'], 600),
            orderTranscript);
      });

      test('negative control: taking b lazily (no snapshot) delivers the write in the same pass, before d', () async {
        gate.check();
        final cpp = await generated('watch_order');
        for (final line in [
          '  const bool unodar_b_changed = b.take();\n',
          '  const int32_t unodar_b_value = b.value();\n',
          'if (unodar_b_changed) {',
          'unodar_watch_1_callback(unodar_b_value)',
        ]) {
          expect(cpp, contains(line), reason: 'the generated code changed; update the negative control');
        }
        final naive = cpp
            .replaceAll('  const bool unodar_b_changed = b.take();\n', '')
            .replaceAll('  const int32_t unodar_b_value = b.value();\n', '')
            .replaceAll('if (unodar_b_changed) {', 'if (b.take()) {')
            .replaceAll('unodar_watch_1_callback(unodar_b_value)', 'unodar_watch_1_callback(b.value())');
        final serial = await run('watch_order', naive, ['D2=low@300', 'D2=open@500'], 600);
        expect(serial, 'a2 0\r\na 0\r\nb 10\r\nd 0\r\na2 1\r\na 1\r\nb 11\r\nd 1\r\n');
      });
    });

    group('Watch chain without a cycle (golden watch_chain, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      const pins = ['D2=low@300', 'D2=open@500'];

      Future<String> run(String cpp) async {
        final build = await compileSketch('watch_chain', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: pins, until: null, cycles: 700 * 16000)).serial;
      }

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'watch_chain', 'input.dart'));
        if (result is! CompileSuccess) fail('watch_chain did not compile with unodar: $result');
        return result.cpp;
      }

      test('each step of a -> b -> c is delivered once, one pass later, and the program is then quiet', () async {
        gate.check();
        expect(
            await run(await generated()),
            'a 0\r\nb 0\r\nc 0\r\n' // setup: every signal starts changed
            'b 100\r\n' // pass 1: the Watch of a wrote b
            'c 1000\r\n' // pass 2: the Watch of b wrote c (copyToC)
            'a 1\r\nb 101\r\nc 1010\r\n'); // one press: one pass per step, then nothing more
      });

      test('negative control: without the snapshot, the chain collapses into one pass', () async {
        gate.check();
        var cpp = await generated();
        for (final s in ['a', 'b', 'c']) {
          for (final line in [
            '  const bool unodar_${s}_changed = $s.take();\n',
            '  const int32_t unodar_${s}_value = $s.value();\n'
          ]) {
            expect(cpp, contains(line), reason: 'the generated code changed; update the negative control');
            cpp = cpp.replaceAll(line, '');
          }
          cpp = cpp.replaceAll('unodar_${s}_changed', '$s.take()').replaceAll('unodar_${s}_value', '$s.value()');
        }
        expect(await run(cpp), 'a 0\r\nb 100\r\nc 1000\r\na 1\r\nb 101\r\nc 1010\r\n');
      });
    });

    group('Led.set from a Watch (golden led_set, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      // Two bouncing presses, stable from 300 ms and 1200 ms.
      const pins = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];

      Future<({String serial, List<String> pinLog})> run(String cpp) async {
        final build = await compileSketch('led_set', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000);
      }

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'led_set', 'input.dart'));
        if (result is! CompileSuccess) fail('led_set did not compile with unodar: $result');
        return result.cpp;
      }

      List<double> changes(List<String> log, String state) => [
            for (final line in log)
              if (line.endsWith(' D13 $state')) double.parse(line.split(' ').first)
          ];

      test('the initial delivery leaves the LED off; each press switches it to whether the count is odd', () async {
        gate.check();
        final result = await run(await generated());
        printOnFailure(result.pinLog.join('\n'));
        expect(result.serial, '0\r\n1\r\n2\r\n');
        // On at press 1 (stable 305 ms + 50 ms debounce), off at press 2 (1200 + 50); millis() may trail by 1 ms.
        expect(changes(result.pinLog, 'high'), [allOf(greaterThanOrEqualTo(354), lessThan(357))]);
        expect(changes(result.pinLog, 'low'), [lessThan(1), allOf(greaterThanOrEqualTo(1249), lessThan(1252))]);
      });

      test('negative control: mapping set() to toggle() lights the LED at boot (the initial delivery)', () async {
        gate.check();
        final cpp = await generated();
        expect(cpp, contains('led.set(unodar_mod(v, 2) == 1);'), reason: 'the generated code changed');
        final result = await run(cpp.replaceAll('led.set(unodar_mod(v, 2) == 1);', 'led.toggle();'));
        expect(changes(result.pinLog, 'high').first, lessThan(1), reason: result.pinLog.join('\n'));
      });
    });

    group('Led(on:) follows its signal (golden led_sink, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      const pins = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];

      Future<({String serial, List<String> pinLog})> run(String cpp) async {
        final build = await compileSketch('led_sink', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000);
      }

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'led_sink', 'input.dart'));
        if (result is! CompileSuccess) fail('led_sink did not compile with unodar: $result');
        return result.cpp;
      }

      List<double> changes(List<String> log, String pin, String state) => [
            for (final line in log)
              if (line.endsWith(' $pin $state')) double.parse(line.split(' ').first)
          ];

      test('pin 13 is lit at the end of setup() and follows lit; pin 12 follows armed; the Watch runs after it',
          () async {
        gate.check();
        final result = await run(await generated());
        printOnFailure(result.pinLog.join('\n'));
        expect(result.serial, 'true\r\nfalse\r\ntrue\r\n');
        // D13: LOW at begin(), HIGH from the setup delivery, LOW at press 1 (305 + 50 ms), HIGH at press 2 (1250).
        expect(changes(result.pinLog, 'D13', 'high'), [lessThan(1), allOf(greaterThanOrEqualTo(1249), lessThan(1252))]);
        expect(changes(result.pinLog, 'D13', 'low'), [lessThan(1), allOf(greaterThanOrEqualTo(354), lessThan(357))]);
        // D12: LOW at begin(), HIGH at press 1; press 2 writes an equal `true`: no change.
        expect(changes(result.pinLog, 'D12', 'high'), [allOf(greaterThanOrEqualTo(354), lessThan(357))]);
        expect(changes(result.pinLog, 'D12', 'low'), [lessThan(1)]);
      });

      test('negative control: signals that do not start changed (no initial delivery) leave pin 13 dark at boot',
          () async {
        gate.check();
        // Removing only the unodar_deliver() call at the end of setup() is not observable here: the signal still
        // starts changed, so the first loop() pass delivers it microseconds later. The wrong model is a signal that
        // starts unchanged (an addListener-style first value), which never delivers the initial value.
        expect(header, contains('value_(initial), changed_(true)'));
        final build = await compileSketch('led_sink', await generated(), files: {
          'unodar_widgets.h': header.replaceAll('value_(initial), changed_(true)', 'value_(initial), changed_(false)')
        });
        expect(build.success, isTrue);
        final result = await simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000);
        expect(changes(result.pinLog, 'D13', 'high'), isNot(contains(lessThan(1))), reason: result.pinLog.join('\n'));
        expect(result.serial, 'false\r\ntrue\r\n');
      });
    });

    group('a Watch callback with a `_` parameter (golden watch_wildcard_parameter, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      const pins = ['D2=low@300', 'D2=open@500'];

      Future<List<String>> highs(String headerText) async {
        final result =
            await Compiler().compile(fromPackage('test', 'golden', 'watch_wildcard_parameter', 'input.dart'));
        if (result is! CompileSuccess) fail('watch_wildcard_parameter did not compile with unodar: $result');
        final build =
            await compileSketch('watch_wildcard_parameter', result.cpp, files: {'unodar_widgets.h': headerText});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final run = await simulate(build.hexPath, pins: pins, until: null, cycles: 600 * 16000);
        printOnFailure(run.pinLog.join('\n'));
        return [
          for (final line in run.pinLog)
            if (line.endsWith(' D13 high') || line.endsWith(' D13 low')) line
        ];
      }

      test('the callback runs at the setup delivery (LED on) and after the press (LED off)', () async {
        gate.check();
        final changes = await highs(header);
        // LOW at begin(), HIGH from the setup delivery, LOW 50 ms after the press settles at 300 ms.
        expect(changes.map((l) => l.split(' ').last), ['low', 'high', 'low']);
        expect(double.parse(changes[1].split(' ').first), lessThan(1));
        expect(double.parse(changes[2].split(' ').first), allOf(greaterThanOrEqualTo(349), lessThan(352)));
      });

      test('negative control: with no initial delivery the LED is not lit at boot', () async {
        gate.check();
        expect(header, contains('value_(initial), changed_(true)'));
        final changes =
            await highs(header.replaceAll('value_(initial), changed_(true)', 'value_(initial), changed_(false)'));
        expect(changes.map((l) => l.split(' ').last), ['low', 'high']);
        expect(double.parse(changes[1].split(' ').first), greaterThan(300));
      });
    });

    group('Computed reads evaluate the expression (golden computed, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      const pins = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'computed', 'input.dart'));
        if (result is! CompileSuccess) fail('computed did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('computed', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000)).serial;
      }

      test('right after the writes, every Computed equals its expression, as in Dart', () async {
        gate.check();
        // Press 1: count 1, level Uint8(250): isOdd true, scaled 1 * 3 + 250 - 1 = 252, half 0.5, label 252.
        // Press 2: count 2, level Uint8(300) = 44: false, 2 * 3 + 44 - 1 = 49, 1.0, label -49.
        expect(await run(await generated()), 'true 252 0.50 252\r\nfalse 49 1.00 -49\r\n');
      });

      test('negative control: reading the stored value instead of evaluating is out of date', () async {
        gate.check();
        final cpp = await generated();
        const read = 'Serial.print(unodar_isOdd_compute() ?';
        expect(cpp, contains(read), reason: 'the generated code changed; update the negative control');
        final serial = await run(cpp.replaceAll(read, 'Serial.print(isOdd.value() ?'));
        expect(serial, startsWith('false 252 '), reason: serial);
      });
    });

    group('delivering a Computed (golden computed_watch, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      // +1 (D2) at 300 ms, +2 (D3) at 800 ms, +1 (D2) at 1300 ms; each stable after the press, released 200 ms later.
      const pins = ['D2=low@300', 'D2=open@500', 'D3=low@800', 'D3=open@1000', 'D2=low@1300', 'D2=open@1500'];

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'computed_watch', 'input.dart'));
        if (result is! CompileSuccess) fail('computed_watch did not compile with unodar: $result');
        return result.cpp;
      }

      Future<({String serial, List<String> pinLog})> run(String cpp) async {
        final build = await compileSketch('computed_watch', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, pins: pins, until: null, cycles: 1600 * 16000);
      }

      List<double> changes(List<String> log, String state) => [
            for (final line in log)
              if (line.endsWith(' D13 $state')) double.parse(line.split(' ').first)
          ];

      test('re-evaluated before any observer runs, delivered only when its value changes; the Led follows it',
          () async {
        gate.check();
        final result = await run(await generated());
        printOnFailure(result.pinLog.join('\n'));
        expect(
            result.serial,
            'count 0\r\nodd false false\r\nother 0\r\n' // setup delivery
            'count 1\r\nodd true true\r\nother 1\r\n' // +1: isOdd settled before its observers, in declaration order
            'count 3\r\n' // +2: isOdd is still true, so it is not delivered
            'count 4\r\nodd false false\r\nother 2\r\n'); // +1
        expect(changes(result.pinLog, 'high'), [allOf(greaterThanOrEqualTo(349), lessThan(352))]);
        expect(changes(result.pinLog, 'low'), [lessThan(1), allOf(greaterThanOrEqualTo(1349), lessThan(1352))]);
      });

      test('negative control: re-evaluating after the observers ran delivers isOdd one pass late, after other',
          () async {
        gate.check();
        final cpp = await generated();
        const recompute = '    isOdd.set(unodar_isOdd_compute());\n';
        expect(cpp, contains(recompute), reason: 'the generated code changed; update the negative control');
        var late = cpp.replaceFirst(recompute, '');
        final deliver = late.indexOf('void unodar_deliver() {');
        final end = late.indexOf('\n}\n', deliver);
        late = late.replaceRange(end, end, '\n  if (unodar_count_changed) { isOdd.set(unodar_isOdd_compute()); }');
        expect(
            (await run(late)).serial,
            'count 0\r\nodd false false\r\nother 0\r\n'
            'count 1\r\nother 1\r\nodd true true\r\n'
            'count 3\r\n'
            'count 4\r\nother 2\r\nodd false false\r\n');
      });
    });

    group('goal program: a debounced Button toggles a Led, Every ticks (compiled by unodar)', () {
      // examples/button_led, the widget example of docs/SUBSET.md: Button on D2 toggles the Led on D13,
      // Every(500 ms) prints `tick`.
      final source = fromPackage('..', '..', 'examples', 'button_led', 'main.dart');
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();

      // Two presses with contact bounce, a bouncing release, and a 20 ms glitch, over 2.6 simulated seconds.
      const inputs = [
        'D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@307', 'D2=low@310', // press 1, stable from 310 ms
        'D2=open@800', 'D2=low@802', 'D2=open@805', // release with bounce
        'D2=low@1200', 'D2=open@1203', 'D2=low@1206', // press 2, stable from 1206 ms
        'D2=open@1600', // release
        'D2=low@2000', 'D2=open@2020', // a 20 ms glitch: not a press
      ];
      const cycles = 2600 * 16000; // 2.6 s at 16 MHz

      Future<({String serial, List<String> pinLog})> run(String headerText) async {
        final result = await Compiler().compile(source);
        if (result is! CompileSuccess) fail('the goal program did not compile with unodar: $result');
        final build = await compileSketch('button_led', result.cpp, files: {'unodar_widgets.h': headerText});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, pins: inputs, until: null, cycles: cycles);
      }

      List<double> changes(List<String> log, String pin, String state) => [
            for (final line in log)
              if (line.endsWith(' $pin $state')) double.parse(line.split(' ').first)
          ];

      test('each bouncing press toggles pin 13 exactly once, 50 ms after it settles; Every ticks 5 times', () async {
        gate.check();
        final result = await run(header);
        printOnFailure(result.pinLog.join('\n'));
        // On at press 1 (stable 310 ms + 50 ms debounce), off at press 2 (1206 + 50). The debounce is measured in
        // millis(), which counts whole 1.024 ms timer overflows at both ends, so allow a millisecond either way.
        expect(changes(result.pinLog, 'D13', 'high'), [allOf(greaterThanOrEqualTo(359), lessThan(362))]);
        expect(changes(result.pinLog, 'D13', 'low'), [lessThan(1), allOf(greaterThanOrEqualTo(1255), lessThan(1258))]);
        // First tick one interval after setup(), then every 500 ms: 500, 1000, 1500, 2000, 2500.
        expect('tick\r\n'.allMatches(result.serial), hasLength(5), reason: result.serial);
        expect(result.serial, 'tick\r\n' * 5);
      });

      test('negative control: without debouncing, the bounces toggle the LED many times', () async {
        gate.check();
        expect(header, contains('kDebounceMs = 50'));
        final result = await run(header.replaceAll('kDebounceMs = 50', 'kDebounceMs = 0'));
        expect(changes(result.pinLog, 'D13', 'high').length, greaterThan(1), reason: result.pinLog.join('\n'));
      });
    });

    test('examples/dial reports the potentiometer reading over Serial', () async {
      gate.check();
      final result = await Compiler().compile(fromPackage('..', '..', 'examples', 'dial', 'main.dart'));
      if (result is! CompileSuccess) fail('examples/dial did not compile with unodar: $result');
      final build = await compileSketch('dial', result.cpp, files: result.files);
      printOnFailure(build.rawOutput);
      expect(build.success, isTrue);
      // 2.5 V on A0 reads 512: the servo angle is 512 * 180 ~/ 1023 = 90, and 512 * 5.0 / 1023 prints as 2.502.
      final output = await runInSimulator(build.hexPath, adc: {0: 2.5}, until: 'volts=2.502');
      expect(output, startsWith('dial ready\r\n'));
      expect(output, contains('level=512 angle=90 volts=2.502'));
    });
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 5)));
}
