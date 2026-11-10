import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';

/// Runs the CLI in-process with captured output.
Future<({int exitCode, String out, String err})> run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final exitCode = await runCli(args, out: out, err: err);
  return (exitCode: exitCode, out: out.toString(), err: err.toString());
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('unodar_cli_test_'));
  tearDown(() => temp.deleteSync(recursive: true));

  final blink = p.join('test', 'golden', 'blink', 'input.dart');

  test('build writes <outdir>/<name>/<name>.ino, prints its path, exits 0', () async {
    final r = await run(['build', blink, '-o', temp.path]);
    final ino = File(p.join(temp.path, 'input', 'input.ino'));
    expect(r.exitCode, 0, reason: r.err);
    expect(r.out.trim(), ino.path);
    expect(r.err, isEmpty);
    expect(ino.readAsStringSync(), File(p.join('test', 'golden', 'blink', 'expected.ino')).readAsStringSync());
  });

  test('diagnostics go to stderr, nothing is written, exit 1', () async {
    final r =
        await run(['build', p.join('test', 'golden', 'e004_non_literal_argument', 'input.dart'), '-o', temp.path]);
    expect(r.exitCode, 1);
    expect(r.out, isEmpty);
    expect(r.err, contains('error[E004]'));
    expect(r.err, endsWith('2 errors.\n'));
    expect(temp.listSync(), isEmpty);
  });

  test('a missing input file is a tooling error, exit 2', () async {
    final r = await run(['build', p.join(temp.path, 'nope.dart'), '-o', temp.path]);
    expect(r.exitCode, 2);
    expect(r.err, contains('file not found'));
  });

  test('usage errors print usage and exit 2', () async {
    expect((await run(['build'])).exitCode, 2);
    expect((await run(['frobnicate'])).exitCode, 2);
    expect((await run([])).exitCode, 2);
  });

  test('--help documents the build command and exits 0', () async {
    final top = await run(['--help']);
    expect(top.exitCode, 0);
    expect(top.out, contains('build'));
    final build = await run(['build', '--help']);
    expect(build.exitCode, 0);
    expect(build.out, contains('--output'));
  });

  test('bin/unodar.dart runs as a real process', () async {
    final result = await Process.run(Platform.resolvedExecutable, ['run', 'bin/unodar.dart', '--help']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout as String, contains('Usage: unodar <command>'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('output is UTF-8 with LF line endings', () async {
    await run(['build', blink, '-o', temp.path]);
    final bytes = File(p.join(temp.path, 'input', 'input.ino')).readAsBytesSync();
    expect(utf8.decode(bytes), isNot(contains('\r')));
  });
}
