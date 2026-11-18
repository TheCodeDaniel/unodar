import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';
import 'package:unodar_compiler/src/version.dart';

import '../fake_arduino_cli.dart';

/// `unodar doctor` against fake toolchains with one fault each (no network, no real arduino-cli).
void main() {
  late Directory temp;
  late String home;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('unodar_doctor_test_');
    home = p.join(temp.path, 'home');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<({int exitCode, String out, String err})> doctor(List<String> args, {String? path}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(['doctor', ...args],
        out: out,
        err: err,
        environment: {'UNODAR_HOME': home, 'PATH': path ?? p.join(temp.path, 'empty'), 'HOME': temp.path},
        workingDirectory: temp.path);
    return (exitCode: code, out: '$out', err: '$err');
  }

  /// A managed toolchain in [home], with a runnable fake avr-gcc where the core puts it.
  FakeArduinoCli managed({Map<String, String>? libraries, Map<String, String>? cores}) {
    final gcc = File(p.join(home, 'data', 'packages', 'arduino', 'tools', 'avr-gcc', '7.3.0', 'bin', 'avr-gcc'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho "avr-gcc (GCC) 7.3.0"\n');
    Process.runSync('chmod', ['+x', gcc.path]);
    return FakeArduinoCli(p.join(home, 'bin'),
        libraries: libraries ??
            const {
              'Servo': '1.3.0',
              'LiquidCrystal': '1.0.7',
              'DHT sensor library': '1.4.7',
              'Adafruit Unified Sensor': '1.1.15'
            },
        cores: cores ?? const {'arduino:avr': '1.8.8'});
  }

  test('nothing installed: every missing piece says `unodar setup`, exit 3', () async {
    final r = await doctor([]);
    expect(r.exitCode, 3, reason: r.out);
    expect(r.out, startsWith('unodar $unodarVersion (Dart '));
    expect(r.out, contains('  ✗ arduino-cli: not installed\n      fix: unodar setup\n'));
    expect(r.out, endsWith('2 problems. Run `unodar setup` to fix them.\n'));
  });

  test('a complete managed toolchain is ready, exit 0', () async {
    managed();
    final r = await doctor([]);
    expect(r.exitCode, 0, reason: r.out);
    expect(r.out, contains('  ✓ arduino-cli 1.5.1 ('));
    expect(r.out, contains('  ✓ core arduino:avr 1.8.8\n'));
    expect(r.out, contains('  ✓ library DHT sensor library 1.4.7\n'));
    expect(r.out, contains('  ✓ avr-gcc (GCC) 7.3.0 runs\n'));
    expect(r.out, contains('  · boards: no Uno plugged in\n'));
    expect(r.out, endsWith('Ready.\n'));
  });

  test('one missing library is one problem with its fix', () async {
    managed(libraries: {'Servo': '1.3.0', 'LiquidCrystal': '1.0.7', 'DHT sensor library': '1.4.7'});
    final r = await doctor([]);
    expect(r.exitCode, 3);
    expect(r.out, contains('  ✗ library Adafruit Unified Sensor: not installed\n      fix: unodar setup\n'));
    expect(r.out, endsWith('1 problem. Run `unodar setup` to fix it.\n'));
  });

  test('a wrong core version is named', () async {
    managed(cores: {'arduino:avr': '1.8.6'});
    final r = await doctor([]);
    expect(r.exitCode, 3);
    expect(r.out, contains('  ✗ core arduino:avr: 1.8.6, but unodar needs 1.8.8\n'));
  });

  test('an arduino-cli on PATH is reported when the managed one is used', () async {
    managed();
    final other = FakeArduinoCli(p.join(temp.path, 'path'), version: '1.4.0');
    final r = await doctor([], path: other.dir);
    expect(r.exitCode, 0, reason: r.out);
    expect(r.out, contains('  · arduino-cli on PATH (${other.executable}): not used\n'));
    expect(other.calls, isEmpty);
  });

  test('a plugged-in Uno is listed', () async {
    managed();
    FakeArduinoCli(p.join(home, 'bin'), ports: [
      {
        'port': {'address': '/dev/cu.usbmodem1101', 'protocol': 'serial'},
        'matching_boards': [
          {'name': 'Arduino Uno', 'fqbn': 'arduino:avr:uno'}
        ],
      }
    ]);
    final r = await doctor([]);
    expect(r.out, contains('  · boards: Uno on /dev/cu.usbmodem1101\n'));
  });

  test('--dev outside a checkout is a problem with its fix', () async {
    managed();
    final r = await doctor(['--dev']);
    expect(r.exitCode, 3);
    expect(r.out, contains('--dev: not inside a unodar checkout'));
  });

  test('doctor --help exits 0 and mentions --dev', () async {
    final r = await doctor(['--help']);
    expect(r.exitCode, 0);
    expect(r.out, contains('--dev'));
  });
}
