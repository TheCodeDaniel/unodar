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

    group('runner device models (Phase 6 step 12, hand-written sketches)', () {
      Future<String> hex(String name) async {
        final source = File(fromPackage('test', 'runtime', 'runner_devices', '$name.ino')).readAsStringSync();
        final build = await compileSketch(name, source);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return build.hexPath;
      }

      test('EEPROM: a second run sees the first run\'s bytes; an update to the same value writes nothing', () async {
        gate.check();
        final program = await hex('eeprom');
        final dir = Directory.systemTemp.createTempSync('unodar_eeprom_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = p.join(dir.path, 'eeprom.bin');
        final writes = p.join(dir.path, 'writes.txt');
        final first = await simulate(program, extra: ['--eeprom', file, '--eeprom-writes', writes]);
        expect(first.serial, 'boot 0\r\nbyte1 42\r\nDONE');
        expect(File(writes).readAsStringSync().trim(), '2', reason: 'byte 0 and the first update of byte 1');
        final second = await simulate(program, extra: ['--eeprom', file, '--eeprom-writes', writes]);
        expect(second.serial, 'boot 1\r\nbyte1 42\r\nDONE');
        expect(File(writes).readAsStringSync().trim(), '1', reason: 'byte 1 already holds 0x42');
      });

      test('negative control: a run without the saved EEPROM file starts erased again', () async {
        gate.check();
        final program = await hex('eeprom');
        final dir = Directory.systemTemp.createTempSync('unodar_eeprom_');
        addTearDown(() => dir.deleteSync(recursive: true));
        await simulate(program, extra: ['--eeprom', p.join(dir.path, 'a.bin')]);
        final fresh = await simulate(program, extra: ['--eeprom', p.join(dir.path, 'b.bin')]);
        expect(fresh.serial, startsWith('boot 0\r\n'));
      });

      test('SPI: the scripted slave answers each byte; the log has the bytes and the SPCR settings', () async {
        gate.check();
        final program = await hex('spi');
        final dir = Directory.systemTemp.createTempSync('unodar_spi_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'spi.log');
        final result = await simulate(program, extra: ['--spi-reply', 'c22017aa', '--spi-log', log]);
        expect(result.serial, 'C2 20 17 \r\nAA\r\nDONE');
        final lines = File(log).readAsLinesSync().map((l) => l.substring(l.indexOf(' ') + 1)).toList();
        expect(lines, [
          '9f c2 mode=1 order=msbFirst divider=16',
          '00 20 mode=1 order=msbFirst divider=16',
          '00 17 mode=1 order=msbFirst divider=16',
          '55 aa mode=3 order=lsbFirst divider=4',
        ]);
      });

      test('negative control: without a script the slave answers 0xFF', () async {
        gate.check();
        final result = await simulate(await hex('spi'), extra: ['--spi-log', '/dev/null']);
        expect(result.serial, 'FF FF FF \r\nFF\r\nDONE');
      });

      /// The HD44780 model's report for [program] (`--lcd-log`), with LiquidCrystal's example wiring.
      Future<List<String>> lcdReport(String program) async {
        final dir = Directory.systemTemp.createTempSync('unodar_lcd_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'lcd.log');
        await simulate(program, extra: ['--lcd', 'D12,D11,D5,D4,D3,D2', '--lcd-log', log]);
        return File(log).readAsLinesSync();
      }

      test('HD44780: LiquidCrystal\'s instructions, screen text, cursor and display shift, no violations', () async {
        gate.check();
        final report = await lcdReport(await hex('lcd'));
        final instructions = [
          for (final l in report)
            if (RegExp(r'^\d+ (cmd8|cmd|data) ').hasMatch(l)) l.substring(l.indexOf(' ') + 1)
        ];
        // The constructor's initialization (16x1), then begin(16, 2)'s, which resynchronizes the chip that is
        // already in 4-bit mode: 0x3, 0x3 read as one byte 0x33 (8-bit), then 0x30 and 0x20 in 8-bit mode.
        expect(instructions.take(15), [
          'cmd8 0x30', 'cmd8 0x30', 'cmd8 0x30', 'cmd8 0x20', 'cmd 0x20', 'cmd 0x0c', 'cmd 0x01', 'cmd 0x06', //
          'cmd 0x33', 'cmd8 0x30', 'cmd8 0x20', 'cmd 0x28', 'cmd 0x0c', 'cmd 0x01', 'cmd 0x06',
        ]);
        expect(report.where((l) => !RegExp(r'^\d+ ').hasMatch(l)), [
          'screen 0 | Hello, world!  |',
          'screen 1 | > 42           |',
          'display on cursor on blink on',
          'cursor row 1 col 2',
          'mode 4-bit lines 2 shift 1',
          'first instruction at 1.027 ms',
          'violations 0',
        ]);
      });

      test('negative control: each broken timing is reported', () async {
        gate.check();
        final report = await lcdReport(await hex('lcd_violations'));
        final violations = [
          for (final l in report)
            if (l.contains(' violation ')) l.substring(l.indexOf('violation ') + 'violation '.length)
        ];
        expect(violations, [
          matches(RegExp(r'^E rose 1\d{3}\.\d us too early, while clear display was busy$')),
          'E pulse of 125 ns (minimum 450 ns)',
          'D4 changed while E was high',
        ]);
        expect(report, contains('violations 3'));
      });

      /// The DHT22 model's report for [program] (`--dht-log`), with the sensor on D2, and the serial output.
      Future<({String serial, List<String> report})> dhtRun(String program, [List<String> options = const []]) async {
        final dir = Directory.systemTemp.createTempSync('unodar_dht_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'dht.log');
        final result =
            await simulate(program, cycles: 4000 * 16000, extra: ['--dht', 'D2', '--dht-log', log, ...options]);
        return (serial: result.serial, report: File(log).readAsLinesSync());
      }

      test('DHT22: DHT sensor library reads the frame the model sends; a forced read 2.5 s later gets a new one',
          () async {
        gate.check();
        final run = await dhtRun(await hex('dht'), ['--dht-reading', '21.5,48.2@0', '--dht-reading', '-3.7,91.0@1000']);
        expect(run.serial, 'ok 21.5 48.2\r\n21.5\r\nok -3.7 91.0\r\nDONE');
        // 48.2 % is 0x01E2, -3.7 degrees 0x8025 (sign bit); the checksum is the low byte of the four bytes' sum
        // (0x03 + 0x8E + 0x80 + 0x25 = 0x136). The library holds the line low for delayMicroseconds(1100), 1.109 or
        // 1.110 ms depending on the build.
        expect([
          for (final l in run.report) l.substring(l.indexOf(' ') + 1)
        ], [
          matches(RegExp(r'^start 1\.1\d\d ms, sent T=21\.5 H=48\.2 frame=01e200d7ba$')),
          matches(RegExp(r'^start 1\.1\d\d ms, sent T=-3\.7 H=91 frame=038e802536$')),
          '0', // the last line, `violations 0`, without its first word
        ]);
      });

      test('negative control: a 0.5 ms start signal is too short; the model reports it and does not answer', () async {
        gate.check();
        final run = await dhtRun(await hex('dht_short_start'));
        expect(run.serial, 'no answer\r\nDONE');
        expect(run.report,
            [matches(RegExp(r'^0\.6\d\d violation start signal 0\.5\d\d ms low \(0\.8 to 20 ms\)$')), 'violations 1']);
      });

      test('cycle-stamped pin log: D13 goes high and low 2 cycles apart', () async {
        gate.check();
        final result = await simulate(await hex('pins_cycles'), extra: ['--pin-log-cycles']);
        int at(String change) => int.parse(result.pinLog.firstWhere((l) => l.endsWith(' $change')).split(' ').first);
        expect(at('D13 low') < at('D13 high'), isTrue, reason: 'pinMode via DDRB: low before the pulse');
        final high = at('D13 high');
        final fall = result.pinLog
            .where((l) => l.endsWith(' D13 low'))
            .map((l) => int.parse(l.split(' ').first))
            .firstWhere((c) => c > high);
        expect(fall - high, 2);
      });

      test('negative control: the millisecond log cannot tell the two changes apart', () async {
        gate.check();
        final result = await simulate(await hex('pins_cycles'));
        final times = [
          for (final l in result.pinLog)
            if (l.endsWith(' D13 high') || l.endsWith(' D13 low')) l.split(' ').first
        ];
        expect(times.sublist(times.length - 2).toSet(), hasLength(1), reason: result.pinLog.join('\n'));
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

    group('two objects of one class keep their own state (golden class_fields, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      // Two bouncing presses on D2 (settled at 305 and 1205 ms); the Every ticks at 500, 1000 and 1500 ms.
      const pins = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'class_fields', 'input.dart'));
        if (result is! CompileSuccess) fail('class_fields did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('class_fields', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000)).serial;
      }

      test('a press changes only left, a tick only right; constructor values, defaults and Uint8 wrap as in Dart',
          () async {
        gate.check();
        // left = Counter(1, scale: 2): step 1 (default), limit Uint8(200), count 10, ratio 0.5.
        // right = Counter(2, step: 5, scale: 3): limit Uint8(300) = 44, count 10, ratio 0.75.
        // Press 1: left.count 110 (not above 200), ratio 1.0. Ticks 1 and 2: right.count 15, 20.
        // Press 2: left.count 210 > 200, so 0 and wrapped; ratio 2.0. Tick 3: right.count 25.
        expect(
            await run(await generated()),
            '1 110 false 1.00 | 2 15 44 0.75\r\n'
            '1 110 false 1.00 | 2 20 44 0.75\r\n'
            '1 0 true 2.00 | 2 25 44 0.75\r\n');
      });

      test('negative control: with count a static member, the two objects share it', () async {
        gate.check();
        final cpp = await generated();
        const field = '  int32_t count = start;\n';
        const end = '      : id(id),\n        step(step),\n        limit(uint8_t(scale * 100)),\n'
            '        ratio(float(scale) / float(4)) {}\n};\n';
        expect(cpp, allOf(contains(field), contains(end)), reason: 'the generated code changed; update the control');
        final shared = cpp
            .replaceFirst(field, '  static int32_t count;\n')
            .replaceFirst(end, '${end}int32_t Counter::count = start;\n');
        // Press 1 makes the shared count 110; tick 1 adds right's step: both print 115.
        expect(await run(shared), startsWith('1 115 false 1.00 | 2 115 44 0.75\r\n'));
      });
    });

    group('a method changes only the object it is called on (golden class_methods, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      // Two bouncing presses on D2 (settled at 305 and 1205 ms); the Every ticks at 500, 1000 and 1500 ms.
      const pins = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'class_methods', 'input.dart'));
        if (result is! CompileSuccess) fail('class_methods did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('class_methods', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000)).serial;
      }

      test('methods call methods, read and write fields with and without this, and getters evaluate as in Dart',
          () async {
        gate.check();
        // small = Meter(1): big when count >= 2. large = Meter(7): big when count >= 14.
        // Press 1: small.add(3): count 3, total 3. Tick 1: large count 7, total 7.
        // Tick 2: large count 14, total 21, big. Press 2: small count 6, total 9. Tick 3: large count 21, total 42.
        expect(
            await run(await generated()),
            '3 3 true\r\n7 7 false\r\n'
            '3 3 true\r\n14 21 true\r\nlarge is big\r\n'
            '6 9 true\r\n21 42 true\r\nlarge is big\r\n');
      });

      test('negative control: a method body that names one object instead of this changes the other object', () async {
        gate.check();
        final cpp = await generated();
        const write = '  this->total += count;\n';
        expect(cpp, contains(write), reason: 'the generated code changed; update the negative control');
        // large.add(1) at tick 1 then adds large's count 7 to small.total (3 + 7) and leaves large.total at 0.
        expect(
            await run(cpp.replaceFirst(write, '  small.total += count;\n')), startsWith('3 10 true\r\n7 0 false\r\n'));
      });
    });

    group('a static field is one variable for the whole class (golden class_static, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      // Two bouncing presses on D2 (settled at 305 and 1205 ms); the Every ticks at 500, 1000 and 1500 ms.
      const pins = ['D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@700', 'D2=low@1200', 'D2=open@1600'];

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'class_static', 'input.dart'));
        if (result is! CompileSuccess) fail('class_static did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('class_static', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, pins: pins, until: null, cycles: 1800 * 16000)).serial;
      }

      test('created counts the hits of both objects, resets is shared, and static constants fold as in Dart', () async {
        gate.check();
        // Press 1: a.count 1, created 1. Tick 1: b.count 1, created 2; report: resets 0, rate * limit 1.5,
        // twiceLimit 6. Tick 2: b.count 2, created 3. Press 2: a.count 2, created 4. Tick 3: b.count reaches the
        // limit 3, so 0 and resets 1; created 5.
        expect(
            await run(await generated()),
            '2 1\r\n0 1.50 6\r\n'
            '3 2\r\n0 1.50 6\r\n'
            '5 0\r\n1 1.50 6\r\n');
      });

      test('negative control: with created an instance field, b counts only its own hits', () async {
        gate.check();
        final cpp = await generated();
        const declaration = '  static int32_t created;\n';
        const definition = 'int32_t Tally::created = 0;\n';
        expect(cpp, allOf(contains(declaration), contains(definition)),
            reason: 'the generated code changed; update the negative control');
        final copied = cpp.replaceFirst(declaration, '  int32_t created = 0;\n').replaceFirst(definition, '');
        // Tick 1: b.created is 1, not 2 (a's hit is in a.created).
        expect(await run(copied), startsWith('1 1\r\n0 1.50 6\r\n'));
      });
    });

    group('a member object is part of its owner, never a copy (golden class_composition, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'class_composition', 'input.dart'));
        if (result is! CompileSuccess) fail('class_composition did not compile with unodar: $result');
        return result.cpp;
      }

      Future<({String serial, List<String> pinLog})> run(String cpp) async {
        final build = await compileSketch('class_composition', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, until: null, cycles: 500 * 16000);
      }

      test('members created in place, used through chains and from methods; the Servo member drives pin 9', () async {
        gate.check();
        final result = await run(await generated());
        // pair = Pair(3): small step 1, large step 30; two rounds, then pair.small.add(): 3 + 60. other = Pair(5):
        // one round, 1 + 50. pair.rounds 2; other.large.step 50; the Servo reads back 90; other's is not attached.
        expect(result.serial, '63\r\n51\r\n2\r\n50\r\n90\r\nfalse\r\n');
        // The Servo member sends pulses on D9, about 1472 µs long for 90 degrees.
        final highs = [
          for (final line in result.pinLog)
            if (line.endsWith(' D9 high')) double.parse(line.split(' ').first)
        ];
        final lows = [
          for (final line in result.pinLog)
            if (line.endsWith(' D9 low')) double.parse(line.split(' ').first)
        ];
        expect(highs.length, greaterThan(5));
        final width = lows.firstWhere((t) => t > highs[1]) - highs[1];
        expect(width, closeTo(1.472, 0.02));
      });

      test('negative control: calling the method on a copy of the member leaves the member unchanged', () async {
        gate.check();
        final cpp = await generated();
        const call = '  this->large.add();\n';
        expect(cpp, contains(call), reason: 'the generated code changed; update the negative control');
        final copied = cpp.replaceFirst(call, '  { Counter copy = this->large; copy.add(); }\n');
        // large never changes: pair.total is 3 + 0, other.total 1 + 0.
        expect((await run(copied)).serial, startsWith('3\r\n1\r\n'));
      });
    });

    group('an enum drives a state machine (golden enum_basics, compiled by unodar)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'enum_basics', 'input.dart'));
        if (result is! CompileSuccess) fail('enum_basics did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('enum_basics', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, until: null, cycles: 1800 * 16000)).serial;
      }

      test('transitions, comparisons, a Signal<Mode> Watch and a 32-bit index product, as in Dart', () async {
        gate.check();
        // Setup delivers idle (0). Tick 1: 10 degrees, heating (1); previous was the const start, cooling. Tick 2:
        // 30 degrees, cooling (2), 2 * 20000 = 40000. Tick 3: still cooling, an equal write, so no delivery.
        expect(
            await run(await generated()),
            'mode 0\r\n'
            '1 1 true 20000 false\r\nmode 1\r\n'
            '2 2 true 40000 false\r\nmode 2\r\n'
            '2 2 true 40000 true\r\n');
      });

      test('negative control: the index product without the 32-bit widening wraps in 16 bits', () async {
        gate.check();
        final cpp = await generated();
        const product = 'uint8_t(mode.value()) * 20000L';
        expect(cpp, contains(product), reason: 'the generated code changed; update the negative control');
        expect(await run(cpp.replaceFirst(product, 'uint8_t(mode.value()) * 20000')),
            contains('2 2 true -25536 false\r\n'));
      });
    });

    group('switch statements on an enum and on ints (golden switch_enum, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'switch_enum', 'input.dart'));
        if (result is! CompileSuccess) fail('switch_enum did not compile with unodar: $result');
        return result.cpp;
      }

      Future<String> run(String cpp) async {
        final build = await compileSketch('switch_enum', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return (await simulate(build.hexPath, until: 'DONE', cycles: 200 * 16000)).serial;
      }

      test('each case runs alone, empty cases share the next body, break and continue as in Dart', () async {
        gate.check();
        // The same program run by the Dart VM prints exactly these lines: score() for idle, heating, cooling, error;
        // classify() for -2 to 6 (default, -1, 0 and 1 sharing a body, the const limit 3, 4 || 5 sharing default's
        // body); count(6), where `continue` skips 2 and `break` leaves only the switch at 4: 0 + 1 + 3 + 4 + 5.
        expect(
            await run(await generated()),
            '0\r\n10\r\n10\r\n-1\r\n'
            '999\r\n100\r\n200\r\n201\r\n999\r\n6\r\n999\r\n999\r\n999\r\n'
            '13\r\nDONE');
      });

      test('negative control: without the break after each case, C++ falls through to the next case', () async {
        gate.check();
        final cpp = await generated();
        expect(cpp, contains('} break;'), reason: 'the generated code changed; update the negative control');
        // classify(-1) now runs every later body too and ends in default's: 999 instead of 100, and so do 0, 1 and 3.
        expect(
            await run(cpp.replaceAll('} break;', '}')),
            '0\r\n10\r\n10\r\n-1\r\n'
            '999\r\n999\r\n999\r\n999\r\n999\r\n999\r\n999\r\n999\r\n999\r\n'
            '13\r\nDONE');
      });
    });

    group('OnStart runs once in setup(), in children order, before the initial delivery (golden on_start)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();

      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'on_start', 'input.dart'));
        if (result is! CompileSuccess) fail('on_start did not compile with unodar: $result');
        return result.cpp;
      }

      Future<({String serial, List<String> pinLog})> run(String cpp) async {
        final build = await compileSketch('on_start', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, until: null, cycles: 100 * 16000);
      }

      double at(List<String> log, String change) =>
          double.parse(log.firstWhere((l) => l.endsWith(' $change'), orElse: () => 'NaN x').split(' ').first);

      test('the first OnStart pulses D12 (delay allowed) before the Led starts; the signal it writes is delivered once',
          () async {
        gate.check();
        final result = await run(await generated());
        // The Watch prints the value written in OnStart, once: the initial delivery comes after every OnStart.
        expect(result.serial, 'start\r\n7\r\n');
        final log = result.pinLog;
        expect(
            at(
                  log,
                  'D12 low',
                ) <
                at(log, 'D13 low'),
            isTrue,
            reason: log.join('\n'));
        // delay(5) inside OnStart: D12 stays high for 5 ms.
        final high = at(log, 'D12 high');
        final low = log.where((l) => l.endsWith(' D12 low')).map((l) => double.parse(l.split(' ').first));
        expect(low.firstWhere((t) => t > high) - high, closeTo(5.0, 0.1));
        // led.begin() (D13 low), then the second OnStart switches it on.
        expect(at(log, 'D13 low') < at(log, 'D13 high'), isTrue);
        expect(at(log, 'D13 high') > low.firstWhere((t) => t > high), isTrue);
      });

      test('negative control: OnStart run after the initial delivery prints the old value first', () async {
        gate.check();
        final cpp = await generated();
        const call = '  unodar_onstart_0_callback();\n';
        const deliver = '  unodar_deliver();\n}\n\n';
        final setup = cpp.indexOf('void setup() {');
        expect(setup, greaterThan(0));
        expect(cpp.indexOf(call, setup), greaterThan(setup), reason: 'the generated code changed; update the control');
        // In setup(): drop the call, and put it back right after unodar_deliver().
        final tail =
            cpp.substring(setup).replaceFirst(call, '').replaceFirst(deliver, '  unodar_deliver();\n$call}\n\n');
        final moved = cpp.substring(0, setup) + tail;
        expect((await run(moved)).serial, '0\r\nstart\r\n7\r\n');
      });
    });

    group('EEPROM keeps its bytes across a reset (golden eeprom, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'eeprom', 'input.dart'));
        if (result is! CompileSuccess) fail('eeprom did not compile with unodar: $result');
        return result.cpp;
      }

      /// Runs the program twice on one EEPROM file (a reset between): the serial output and byte writes of each run.
      Future<List<(String, int)>> twice(String cpp) async {
        final build = await compileSketch('eeprom', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final dir = Directory.systemTemp.createTempSync('unodar_eeprom_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = p.join(dir.path, 'eeprom.bin');
        final writes = p.join(dir.path, 'writes.txt');
        return [
          for (var run = 0; run < 2; run++)
            (
              (await simulate(build.hexPath, extra: ['--eeprom', file, '--eeprom-writes', writes])).serial,
              int.parse(File(writes).readAsStringSync().trim()),
            ),
        ];
      }

      test('the second run reads the first run\'s count; update writes only a changed byte', () async {
        gate.check();
        // Run 1: erased (255, so 0), writes byte 0 and the first update of byte 1: 2 writes. Run 2: reads 1, writes
        // byte 0; byte 1 already holds 66, so both updates write nothing: 1 write.
        expect(await twice(await generated()), [
          ('boot 0\r\nsize 1024\r\nDONE', 2),
          ('boot 1\r\nsize 1024\r\nDONE', 1),
        ]);
      });

      test('negative control: update bound to write writes the unchanged byte on every call', () async {
        gate.check();
        final cpp = await generated();
        expect(cpp, contains('EEPROM.update('), reason: 'the generated code changed; update the negative control');
        final runs = await twice(cpp.replaceAll('EEPROM.update(', 'EEPROM.write('));
        expect(runs.map((r) => r.$2), [3, 3]);
      });
    });

    group('SPI shim (runtime/unodar_spi.h, hand-written sketch)', () {
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_spi.h')).readAsStringSync();
      final sketch = File(fromPackage('test', 'runtime', 'spi_shim', 'spi_shim.ino')).readAsStringSync();

      /// The serial output and the SPI log lines without their cycle stamps.
      Future<(String, List<String>)> run(String shim) async {
        final build = await compileSketch('spi_shim', sketch, files: {'unodar_spi.h': shim});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final dir = Directory.systemTemp.createTempSync('unodar_spi_shim_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'spi.log');
        final result = await simulate(build.hexPath, extra: ['--spi-reply', 'a0a1a2a3b0c1c2', '--spi-log', log]);
        return (result.serial, [for (final l in File(log).readAsLinesSync()) l.substring(l.indexOf(' ') + 1)]);
      }

      test('mode n is SPI_MODEn, the bit order and clock divider are SPISettings\', transfer16 is MSB first', () async {
        gate.check();
        final (serial, lines) = await run(header);
        expect(serial, 'C1C2\r\noff\r\nDONE');
        expect(lines, [
          '10 a0 mode=0 order=msbFirst divider=8',
          '11 a1 mode=1 order=msbFirst divider=8',
          '12 a2 mode=2 order=msbFirst divider=8',
          '13 a3 mode=3 order=msbFirst divider=8',
          '20 b0 mode=2 order=lsbFirst divider=128',
          '12 c1 mode=0 order=msbFirst divider=2',
          '34 c2 mode=0 order=msbFirst divider=2',
        ]);
      });

      test('negative control: the mode passed unshifted (as SPI_MODEn values) is mode 0 for 1, 2 and 3', () async {
        gate.check();
        const shift = 'uint8_t(mode << 2)';
        expect(header, contains(shift), reason: 'the shim changed; update the negative control');
        final (_, lines) = await run(header.replaceAll(shift, 'mode'));
        expect(lines.take(4).map((l) => l.split(' ')[2]), ['mode=0', 'mode=0', 'mode=0', 'mode=0']);
      });
    });

    group('SPI talks to a device (golden spi, compiled by unodar)', () {
      Future<CompileSuccess> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'spi', 'input.dart'));
        if (result is! CompileSuccess) fail('spi did not compile with unodar: $result');
        return result;
      }

      /// The serial output, the SPI log and the pin log, each line with its cycle stamp.
      Future<(String, List<String>, List<String>)> run(String cpp, Map<String, String> files) async {
        final build = await compileSketch('spi', cpp, files: files);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final dir = Directory.systemTemp.createTempSync('unodar_spi_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'spi.log');
        final result =
            await simulate(build.hexPath, extra: ['--spi-reply', 'ffc22017aa', '--spi-log', log, '--pin-log-cycles']);
        return (result.serial, File(log).readAsLinesSync(), result.pinLog);
      }

      test('the slave\'s JEDEC ID is read inside one chip select, then a mode 3 LSB-first byte', () async {
        gate.check();
        final result = await generated();
        expect(result.files.keys, ['unodar_spi.h'], reason: 'the shim is written next to the sketch');
        final (serial, spi, pins) = await run(result.cpp, result.files);
        expect(serial, '${0xC2 * 65536 + 0x2017}\r\nDONE');
        expect([
          for (final l in spi) l.substring(l.indexOf(' ') + 1)
        ], [
          '9f ff mode=0 order=msbFirst divider=4',
          '00 c2 mode=0 order=msbFirst divider=4',
          '00 20 mode=0 order=msbFirst divider=4',
          '00 17 mode=0 order=msbFirst divider=4',
          'a5 aa mode=3 order=lsbFirst divider=16',
        ]);
        // Chip select: D10 low before the first byte of the ID, high after its last, and high again for the A5.
        int cycle(String line) => int.parse(line.split(' ').first);
        final select = [
          for (final l in pins)
            if (l.contains(' D10 ')) l
        ];
        final low = select.where((l) => l.endsWith(' low')).map(cycle).toList();
        final high = select.where((l) => l.endsWith(' high')).map(cycle).toList();
        final bytes = spi.map(cycle).toList();
        expect(low.where((c) => c < bytes.first), isNotEmpty, reason: select.join('\n'));
        expect(high.where((c) => c > bytes[3] && c < bytes[4]), isNotEmpty, reason: select.join('\n'));
        expect(low.where((c) => c > bytes[3]), isEmpty, reason: 'the A5 is sent without selecting the chip');
      });

      test('negative control: SPI_MODE3 passed as Arduino\'s value (0x0C) is out of range for the shim', () async {
        gate.check();
        final result = await generated();
        const mode3 = 'uint8_t(3)';
        expect(result.cpp, contains(mode3), reason: 'the generated code changed; update the negative control');
        // What a binding of SPI_MODE3 to the C++ macro would emit: the shim shifts 0x0C out of the mode bits.
        final (_, spi, _) = await run(result.cpp.replaceAll(mode3, 'uint8_t(SPI_MODE3)'), result.files);
        expect(spi.last.split(' ')[3], 'mode=0');
      });
    });

    group('@CppPrint gives a Print binding Serial\'s dispatch (golden cpp_print, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'cpp_print', 'input.dart'));
        if (result is! CompileSuccess) fail('cpp_print did not compile with unodar: $result');
        return result.cpp;
      }

      /// The text SoftwareSerial sent on D11 at 9600 baud, with D2 held low (so `ready` is true).
      Future<String> run(String cpp) async {
        final build = await compileSketch('cpp_print', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        // The output is not on the USART, so --until cannot stop the run: 0.15 s is enough for about 60 bytes.
        final result = await simulate(build.hexPath,
            pins: ['D2=low@0'], until: null, cycles: 2400000, extra: ['--pin-log-cycles']);
        final uart = decodeUart(result.pinLog, 'D11', 9600);
        expect(uart.framingErrors, 0);
        return String.fromCharCodes(uart.bytes);
      }

      test('a bool prints true/false, a double its digits, a Uint8 its number, println(\'\') a line break', () async {
        gate.check();
        expect(await run(await generated()), 'ready true\r\nfalse\r\n0.3333 -42\r\n200\r\n\r\nDONE\r\n');
      });

      test('negative control: Arduino\'s plain print(bool) prints 1 and 0', () async {
        gate.check();
        final cpp = await generated();
        const dispatch = 'link.println(ready ? F("true") : F("false"));';
        expect(cpp, contains(dispatch), reason: 'the generated code changed; update the negative control');
        final text = await run(cpp
            .replaceAll(dispatch, 'link.println(ready);')
            .replaceAll('link.println(!ready ? F("true") : F("false"));', 'link.println(!ready);'));
        expect(text, startsWith('ready 1\r\n0\r\n'));
      });
    });

    group('SoftwareSerial sends and receives on its pins (golden software_serial, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'software_serial', 'input.dart'));
        if (result is! CompileSuccess) fail('software_serial did not compile with unodar: $result');
        return result.cpp;
      }

      /// `--pin` edges that send [bytes] (8N1, idle high) on [pin] at [baud], from [startMs] on.
      List<String> uartEdges(String pin, List<int> bytes, int baud, double startMs) {
        final bitMs = 1000 / baud;
        final edges = ['$pin=high@0'];
        var level = true;
        var t = startMs;
        for (final byte in bytes) {
          final bits = [false, for (var b = 0; b < 8; b++) byte & (1 << b) != 0, true];
          for (final (k, high) in bits.indexed) {
            if (high != level) edges.add('$pin=${high ? 'high' : 'low'}@${(t + k * bitMs).toStringAsFixed(4)}');
            level = high;
          }
          t += 10 * bitMs + 0.05; // a short idle gap between bytes, as a real sender may leave
        }
        return edges;
      }

      // 70 digits, sent on D10 from 30 ms on, after the program's own sending is over (sending blocks receiving).
      final incoming = [for (var i = 0; i < 70; i++) 0x30 + i % 10];

      Future<({String serial, List<String> pinLog})> run(String cpp, {int rxBaud = 9600}) async {
        final build = await compileSketch('software_serial', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath,
            pins: uartEdges('D10', incoming, rxBaud, 30), cycles: 8000000, extra: ['--pin-log-cycles']);
      }

      test('TX of both ports decoded from their pins; RX keeps 63 bytes and reports the overflow', () async {
        gate.check();
        final result = await run(await generated());
        final gps = decodeUart(result.pinLog, 'D11', 9600);
        final radio = decodeUart(result.pinLog, 'D9', 9600);
        expect(String.fromCharCodes(gps.bytes), 'gps true\r\nA');
        expect(String.fromCharCodes(radio.bytes), 'radio\r\n', reason: 'the member object sends on its own pin');
        expect([gps.framingErrors, radio.framingErrors], [0, 0]);
        printOnFailure('largest TX edge error: ${gps.maxEdgeError} bit');
        expect(gps.maxEdgeError, lessThan(0.05), reason: 'bit timing within 5 % of a bit at 9600 baud');
        // The ring buffer holds 63 of the 70; the 63rd byte is digit 2.
        expect(result.serial, 'overflow true\r\nkept 63\r\nlast ${0x30 + 62 % 10}\r\nempty -1\r\nDONE');
      });

      test('negative control: bytes sent at the wrong baud (4800) are not received as sent', () async {
        gate.check();
        final result = await run(await generated(), rxBaud: 4800);
        expect(result.serial, isNot(contains('last ${0x30 + 62 % 10}\r\n')), reason: result.serial);
        final wrong = decodeUart(result.pinLog, 'D11', 4800);
        expect(String.fromCharCodes(wrong.bytes), isNot('gps true\r\nA'), reason: 'TX decoded at the wrong baud');
      });

      test('at 115200 baud, the fastest begin() accepts, TX stays within a receiver\'s tolerance', () async {
        gate.check();
        final cpp = (await generated()).replaceAll('gps.begin(9600);', 'gps.begin(115200);');
        final result = await run(cpp);
        final gps = decodeUart(result.pinLog, 'D11', 115200);
        printOnFailure('largest TX edge error at 115200: ${gps.maxEdgeError} bit');
        expect(String.fromCharCodes(gps.bytes), 'gps true\r\nA');
        expect(gps.maxEdgeError, lessThan(0.25));
      });
    });

    group('LiquidCrystal drives an HD44780 (golden liquid_crystal, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'liquid_crystal', 'input.dart'));
        if (result is! CompileSuccess) fail('liquid_crystal did not compile with unodar: $result');
        return result.cpp;
      }

      /// The HD44780 model's report: instruction lines (`<cycle> cmd|cmd8|data 0x..`) and the final state.
      Future<List<String>> run(String cpp) async {
        final build = await compileSketch('liquid_crystal', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final dir = Directory.systemTemp.createTempSync('unodar_lcd_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'lcd.log');
        await simulate(build.hexPath, extra: ['--lcd', 'D12,D11,D5,D4,D3,D2', '--lcd-log', log]);
        return File(log).readAsLinesSync();
      }

      List<String> state(List<String> report) => [
            for (final l in report)
              if (!RegExp(r'^\d+ ').hasMatch(l) && !l.startsWith('first instruction')) l
          ];

      test('the exact screen text, cursor and flags, and no timing violation', () async {
        gate.check();
        final report = await run(await generated());
        expect(state(report), [
          'screen 0 |Temp 21.5{df}C     |',
          'screen 1 |Heater true     |',
          'display on cursor on blink off',
          'cursor row 1 col 15',
          'mode 4-bit lines 2 shift 0',
          'violations 0',
        ]);
        // The waits, measured: the gap after clear() and home(), and between two characters.
        final instructions = [
          for (final l in report)
            if (RegExp(r'^\d+ (cmd|data) ').hasMatch(l)) (int.parse(l.split(' ')[0]), l.split(' ').skip(1).join(' '))
        ];
        double gapUs(int i) => (instructions[i + 1].$1 - instructions[i].$1) / 16;
        final clear = instructions.lastIndexWhere((i) => i.$2 == 'cmd 0x01');
        final home = instructions.lastIndexWhere((i) => i.$2 == 'cmd 0x02');
        final characters = [
          for (var i = 0; i + 1 < instructions.length; i++)
            if (instructions[i].$2.startsWith('data') && instructions[i + 1].$2.startsWith('data')) gapUs(i)
        ];
        printOnFailure('clear ${gapUs(clear)} us, home ${gapUs(home)} us, characters $characters us');
        expect(gapUs(clear), inInclusiveRange(1520, 2300));
        expect(gapUs(home), inInclusiveRange(1520, 2300));
        expect(characters, everyElement(inInclusiveRange(280, 400)), reason: 'two E pulses, each with a 100 us wait');
      });

      test('negative control: setCursor with column and row swapped writes the second line into the first', () async {
        gate.check();
        final cpp = await generated();
        const call = 'lcd.setCursor(0, 1);';
        expect(cpp, contains(call), reason: 'the generated code changed; update the negative control');
        final report = await run(cpp.replaceAll(call, 'lcd.setCursor(1, 0);'));
        expect(state(report).take(2), ['screen 0 |THeater true    |', 'screen 1 |                |']);
      });
    });

    group('a DHT22 read through the DHT wrapper (golden dht, compiled by unodar)', () {
      Future<String> generated() async {
        final result = await Compiler().compile(fromPackage('test', 'golden', 'dht', 'input.dart'));
        if (result is! CompileSuccess) fail('dht did not compile with unodar: $result');
        return result.cpp;
      }

      /// The serial output, the DHT22 model's report and the pin log (ms) of [cpp], with the sensor on D2.
      Future<({String serial, List<String> report, List<String> pinLog})> run(String cpp,
          [List<String> options = const []]) async {
        final build = await compileSketch('dht', cpp);
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final dir = Directory.systemTemp.createTempSync('unodar_dht_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final log = p.join(dir.path, 'dht.log');
        final result =
            await simulate(build.hexPath, cycles: 4000 * 16000, extra: ['--dht', 'D2', '--dht-log', log, ...options]);
        return (serial: result.serial, report: File(log).readAsLinesSync(), pinLog: result.pinLog);
      }

      test('the values, the 2 s cache (one exchange for four reads), the conversions, and millis() ticks lost',
          () async {
        gate.check();
        final result = await run(await generated());
        // 21.5 C is 70.70 F; the heat index of 30 C at 70 % is 35.04 C (Rothfusz, as computed independently).
        expect(
            result.serial,
            'true 21.5 48.2\r\ntrue 21.5 48.2\r\n70.70\r\n35.04\r\n212.0\r\n100.0\r\n'
            '2103\r\nDONE');
        // Two exchanges: the first report() (the second one, readTemperature(fahrenheit: true) and the reads inside
        // each report() use the cached result), and the forced read 2.1 s later.
        final starts = [
          for (final l in result.report)
            if (l.contains(' start ')) double.parse(l.split(' ').first)
        ];
        expect(starts.length, 2);
        expect(starts.last - starts.first, inInclusiveRange(2100, 2120));
        expect(result.report.last, 'violations 0');
        // Pin 13 stamps the simulated time around delay(2100) and the forced exchange: millis() counted 2103 ms of
        // it. The difference is the timer interrupts lost while the exchange kept interrupts off.
        double at(String change) => double.parse(result.pinLog.lastWhere((l) => l.endsWith(change)).split(' ')[0]);
        final simulated = at(' D13 low') - at(' D13 high');
        printOnFailure('simulated $simulated ms, millis() 2103 ms');
        expect((simulated - 2103).round(), 3, reason: 'about 3 ms of millis() lost per exchange');
      });

      test('a frame with a bad checksum reads as false and NaN', () async {
        gate.check();
        final result = await run(await generated(), ['--dht-bad-checksum']);
        expect(result.serial, startsWith('false nan nan\r\nfalse nan nan\r\nnan\r\n'));
      });

      test('negative control: 1 bits sent shorter than the 50 us low time decode as 0s (a wrong bit threshold)',
          () async {
        gate.check();
        // Every bit then reads 0: an all-zero frame has a valid checksum, so read() succeeds with 0.0 and 0.0.
        final result = await run(await generated(), ['--dht-one-us', '45']);
        expect(result.serial, startsWith('true 0.0 0.0\r\n'));
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

    group('goal program: a signal, a Computed, a bound Led and a Watch (examples/counter, compiled by unodar)', () {
      // examples/counter, the signals example of docs/SUBSET.md: +1 on D2, clear on D3, the LED on D13 follows
      // isOdd, a Watch prints the count. Every press bounces; each is stable 5 ms after it starts.
      final source = fromPackage('..', '..', 'examples', 'counter', 'main.dart');
      final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
      const inputs = [
        'D2=low@300', 'D2=open@302', 'D2=low@305', 'D2=open@600', // +1 -> 1, stable from 305 ms
        'D2=low@900', 'D2=open@902', 'D2=low@905', 'D2=open@1200', // +1 -> 2, from 905 ms
        'D3=low@1500', 'D3=open@1502', 'D3=low@1505', 'D3=open@1800', // clear -> 0, from 1505 ms
        'D3=low@2100', 'D3=open@2102', 'D3=low@2105', 'D3=open@2400', // clear at 0: an equal write
        'D2=low@2700', 'D2=open@2702', 'D2=low@2705', 'D2=open@3000', // +1 -> 1, from 2705 ms
      ];
      const cycles = 3100 * 16000; // 3.1 s at 16 MHz

      Future<({String serial, List<String> pinLog})> run(String headerText) async {
        final result = await Compiler().compile(source);
        if (result is! CompileSuccess) fail('examples/counter did not compile with unodar: $result');
        final build = await compileSketch('counter', result.cpp, files: {'unodar_widgets.h': headerText});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        return simulate(build.hexPath, pins: inputs, until: null, cycles: cycles);
      }

      List<double> changes(List<String> log, String state) => [
            for (final line in log)
              if (line.endsWith(' D13 $state')) double.parse(line.split(' ').first)
          ];

      test('prints 0, then each new count once; the clear at 0 prints nothing; pin 13 is lit while odd', () async {
        gate.check();
        final result = await run(header);
        printOnFailure(result.pinLog.join('\n'));
        expect(result.serial, '0\r\n1\r\n2\r\n0\r\n1\r\n');
        // 50 ms after each press settles; millis() may trail the simulated time by a millisecond.
        Matcher at(int ms) => allOf(greaterThanOrEqualTo(ms - 1), lessThan(ms + 2));
        expect(changes(result.pinLog, 'high'), [at(355), at(2755)]);
        expect(changes(result.pinLog, 'low'), [lessThan(1), at(955)]);
      });

      test('negative control: with equal writes delivered, the clear at 0 prints a second 0', () async {
        gate.check();
        expect(header, contains('if (value != value_) {'));
        final result = await run(header.replaceAll('if (value != value_) {', 'if (true) {'));
        expect(result.serial, '0\r\n1\r\n2\r\n0\r\n0\r\n1\r\n');
      });
    });

    group('goal program: the thermostat (examples/thermostat, compiled by unodar)', () {
      // examples/thermostat, the Phase 6 goal program: a DHT22 on D8 read every 2.5 s, the heater on D13, buttons up
      // on D6 and down on D7, an HD44780 on D12, D11, D5, D4, D3, D2, the setpoint in EEPROM byte 0.
      final source = fromPackage('..', '..', 'examples', 'thermostat', 'main.dart');
      // Bouncing presses: up, up, down (21 -> 22 -> 23 -> 22), each stable 4 or 5 ms after it starts.
      const presses = [
        '--pin', 'D6=low@500', '--pin', 'D6=open@502', '--pin', 'D6=low@504', '--pin', 'D6=open@650', //
        '--pin', 'D6=low@1000', '--pin', 'D6=open@1003', '--pin', 'D6=low@1005', '--pin', 'D6=open@1150', //
        '--pin', 'D7=low@1500', '--pin', 'D7=open@1502', '--pin', 'D7=low@1504', '--pin', 'D7=open@1650',
      ];
      // The temperature sweep, against the setpoint 22 and hysteresis 1 (heat below 21, stop above 23). Readings
      // are taken at 2.5, 5, 7.5, 10 and 12.5 s: 18.0 heats; 22.5 keeps heating; 23.5 stops; 21.5 stays idle;
      // 20.5 heats again.
      const sweep = [
        '--dht-reading', '18.0,40.0@0', '--dht-reading', '22.5,40.0@4000', '--dht-reading', '23.5,40.0@6500', //
        '--dht-reading', '21.5,40.0@9000', '--dht-reading', '20.5,40.0@11500',
      ];

      Future<String> generated() async {
        final result = await Compiler().compile(source);
        if (result is! CompileSuccess) fail('examples/thermostat did not compile with unodar: $result');
        return result.cpp;
      }

      /// Runs [cpp] for [ms] simulated milliseconds with [eeprom] as its EEPROM file, and returns the LCD's final
      /// state, the DHT22 model's report, the EEPROM writes of the run and the D13 (heater) changes in ms.
      Future<({List<String> lcd, List<String> dht, int writes, List<String> heater})> run(
          String cpp, String eeprom, int ms, List<String> options) async {
        final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
        final build = await compileSketch('thermostat', cpp, files: {'unodar_widgets.h': header});
        printOnFailure(build.rawOutput);
        expect(build.success, isTrue);
        final dir = Directory.systemTemp.createTempSync('unodar_thermostat_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final lcd = p.join(dir.path, 'lcd.log');
        final dht = p.join(dir.path, 'dht.log');
        final writes = p.join(dir.path, 'writes.txt');
        final result = await simulate(build.hexPath, until: null, cycles: ms * 16000, extra: [
          '--lcd', 'D12,D11,D5,D4,D3,D2', '--lcd-log', lcd, '--dht', 'D8', '--dht-log', dht, //
          '--eeprom', eeprom, '--eeprom-writes', writes, ...options,
        ]);
        return (
          lcd: [
            for (final l in File(lcd).readAsLinesSync())
              if (!RegExp(r'^\d+ ').hasMatch(l) && !l.startsWith('first instruction')) l
          ],
          dht: File(dht).readAsLinesSync(),
          writes: int.parse(File(writes).readAsStringSync().trim()),
          heater: [
            for (final l in result.pinLog)
              if (l.contains(' D13 ')) l
          ],
        );
      }

      /// The heater's changes after boot (the first line is pinMode's LOW in setup()), as (state, ms) pairs.
      List<(String, double)> switches(List<String> heater) =>
          [for (final l in heater.skip(1)) (l.split(' ')[2], double.parse(l.split(' ')[0]))];

      test('presses move the setpoint, the heater follows the hysteresis rule, the LCD shows it, EEPROM keeps it',
          () async {
        gate.check();
        final dir = Directory.systemTemp.createTempSync('unodar_thermostat_ee_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final eeprom = p.join(dir.path, 'eeprom.bin');
        final cpp = await generated();
        final first = await run(cpp, eeprom, 13500, [...presses, ...sweep]);
        expect(first.lcd, [
          'screen 0 |Temp 20.5       |',
          'screen 1 |Set 22  heating |',
          'display on cursor off blink off',
          'cursor row 1 col 15',
          'mode 4-bit lines 2 shift 0',
          'violations 0',
        ]);
        expect(first.dht.where((l) => l.contains(' start ')).length, 5);
        expect(first.dht.last, 'violations 0');
        // A tick 2.5 s apart in millis() is 2.5 s plus the 3 ms each exchange costs millis() in simulated time.
        Matcher near(int ms) => inInclusiveRange(ms, ms + 50);
        final heater = switches(first.heater);
        expect(heater.map((s) => s.$1), ['high', 'low', 'high']);
        expect(heater.map((s) => s.$2), [near(2500), near(7500), near(12500)]);
        // The initial delivery writes 21 onto the erased byte, then each press writes once: 22, 23, 22.
        expect(first.writes, 4);
        expect(File(eeprom).readAsBytesSync().first, 22);

        // A reset: the same EEPROM, no presses, 21.5 degrees. The saved setpoint is shown at boot, 21.5 is not below
        // 21, and updating byte 0 with the value it holds writes nothing.
        final second = await run(cpp, eeprom, 3000, ['--dht-reading', '21.5,40.0@0']);
        expect(second.lcd.take(2), ['screen 0 |Temp 21.5       |', 'screen 1 |Set 22  idle    |']);
        expect(second.writes, 0);
        expect(switches(second.heater), isEmpty);
      });

      test('a failed reading (bad checksum) shows an error and keeps the heater off', () async {
        gate.check();
        final dir = Directory.systemTemp.createTempSync('unodar_thermostat_ee_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final result = await run(await generated(), p.join(dir.path, 'eeprom.bin'), 3000,
            ['--dht-reading', '18.0,40.0@0', '--dht-bad-checksum']);
        expect(result.lcd.take(2), ['screen 0 |Temp error      |', 'screen 1 |Set 21          |']);
        expect(switches(result.heater), isEmpty);
      });

      test('negative control: without the hysteresis on the way up, the heater stops at 22.5 instead of 23.5',
          () async {
        gate.check();
        final cpp = await generated();
        const stop = 'temperature > target + hysteresis';
        expect(cpp, contains(stop), reason: 'the generated code changed; update the negative control');
        final dir = Directory.systemTemp.createTempSync('unodar_thermostat_ee_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final result = await run(
            cpp.replaceFirst(stop, 'temperature > target'), p.join(dir.path, 'e.bin'), 13500, [...presses, ...sweep]);
        final heater = switches(result.heater);
        expect(heater.map((s) => s.$1), ['high', 'low', 'high']);
        expect(heater[1].$2, inInclusiveRange(5000, 5050), reason: 'off at the 5 s reading (22.5 > 22)');
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
