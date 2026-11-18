import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';

import '../fake_arduino_cli.dart';
import '../test_paths.dart';

/// `unodar flash` with a fake arduino-cli: which port it uploads to, the exact upload call, and exit 4 for every
/// board problem. A real upload needs a real board (the maintainer's checklist).
void main() {
  late Directory temp;
  late String home;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('unodar_flash_test_');
    home = p.join(temp.path, 'home');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  final blink = fromPackage('test', 'golden', 'blink', 'input.dart');

  List<Map<String, Object?>> ports(String fixture) =>
      ((jsonDecode(File(fromPackage('test', 'fixtures', 'board_list', '$fixture.json')).readAsStringSync())
              as Map<String, Object?>)['detected_ports'] as List<Object?>)
          .cast<Map<String, Object?>>();

  Future<({int exitCode, String out, String err})> flash(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(['flash', blink, '-o', 'out', ...args],
        out: out,
        err: err,
        environment: {'UNODAR_HOME': home, 'PATH': p.join(temp.path, 'empty'), 'HOME': temp.path},
        workingDirectory: temp.path);
    return (exitCode: code, out: '$out', err: '$err');
  }

  String uploadCall(FakeArduinoCli fake) => fake.calls.singleWhere((c) => c.startsWith('upload'));

  test('builds, then uploads the build to the one Uno plugged in, exit 0', () async {
    final fake = FakeArduinoCli(p.join(home, 'bin'), ports: ports('one_uno'));
    final r = await flash([]);
    expect(r.exitCode, 0, reason: r.err);
    expect(
        uploadCall(fake),
        'upload --fqbn arduino:avr:uno --port /dev/cu.usbmodem1101 '
        '--input-dir ${p.join(temp.path, 'out', '.build', 'input')} '
        '--config-file ${p.join(home, 'arduino-cli.yaml')}');
    expect(r.out, endsWith('Uploading to /dev/cu.usbmodem1101...\nDone: the program is running on the board.\n'));
    expect(fake.calls.indexWhere((c) => c.startsWith('compile')), lessThan(fake.calls.indexOf(uploadCall(fake))));
  });

  test('--port skips the detection', () async {
    final fake = FakeArduinoCli(p.join(home, 'bin'));
    final r = await flash(['--port', '/dev/ttyUSB7']);
    expect(r.exitCode, 0, reason: r.err);
    expect(uploadCall(fake), contains('--port /dev/ttyUSB7 '));
    expect(fake.calls.where((c) => c.startsWith('board list')), isEmpty);
  });

  test('no board: exit 4, nothing uploaded', () async {
    final fake = FakeArduinoCli(p.join(home, 'bin'), ports: ports('none'));
    final r = await flash([]);
    expect(r.exitCode, 4);
    expect(r.err, contains('No Arduino Uno found.'));
    expect(fake.calls.where((c) => c.startsWith('upload')), isEmpty);
  });

  test('a clone is listed with its --port line but not chosen: exit 4', () async {
    final fake = FakeArduinoCli(p.join(home, 'bin'), ports: ports('clone'));
    final r = await flash([]);
    expect(r.exitCode, 4);
    expect(r.err, contains('unodar flash --port /dev/cu.wchusbserial1410'));
    expect(fake.calls.where((c) => c.startsWith('upload')), isEmpty);
  });

  test('two Unos: exit 4, both listed', () async {
    FakeArduinoCli(p.join(home, 'bin'), ports: ports('two_unos'));
    final r = await flash([]);
    expect(r.exitCode, 4);
    expect(r.err, contains('--port /dev/ttyACM1'));
  });

  test('a busy port gets its own message, exit 4', () async {
    FakeArduinoCli(p.join(home, 'bin'),
        ports: ports('one_uno'),
        uploadError: 'avrdude: ser_open(): cannot open port /dev/cu.usbmodem1101: Resource busy\n'
            'Failed uploading: uploading error: exit status 1\n');
    final r = await flash([]);
    expect(r.exitCode, 4);
    expect(r.err, contains('Resource busy'));
    expect(r.err, contains('close any serial monitor'));
  });

  test('a board that does not answer gets the bootloader hint, exit 4', () async {
    FakeArduinoCli(p.join(home, 'bin'),
        ports: ports('one_uno'), uploadError: 'avrdude: stk500_recv(): programmer is not responding\n');
    final r = await flash([]);
    expect(r.exitCode, 4);
    expect(r.err, contains('did not answer'));
  });

  test('a diagnostic stops before any board is looked for, exit 1', () async {
    final fake = FakeArduinoCli(p.join(home, 'bin'), ports: ports('one_uno'));
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
        ['flash', fromPackage('test', 'golden', 'e004_argument_out_of_range', 'input.dart'), '-o', 'out'],
        out: out,
        err: err,
        environment: {'UNODAR_HOME': home, 'PATH': ''},
        workingDirectory: temp.path);
    expect(code, 1);
    expect(fake.calls, isEmpty);
  });

  test('no toolchain: exit 3', () async {
    final r = await flash([]);
    expect(r.exitCode, 3);
  });
}
