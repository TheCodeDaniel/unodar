import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';

import '../fake_arduino_cli.dart';
import '../test_paths.dart';

/// `unodar build` with a fake arduino-cli: it compiles what it wrote, prints the sizes, and maps each failure to its
/// exit code. The real compile is in `cli_build_test.dart` (tagged `arduino`).
void main() {
  late Directory temp;
  late String home;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('unodar_build_test_');
    home = p.join(temp.path, 'home');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  final blink = fromPackage('test', 'golden', 'blink', 'input.dart');
  final escapeHatch = fromPackage('test', 'golden', 'cpp_escape_hatch', 'input.dart');

  Future<({int exitCode, String out, String err})> build(List<String> args, {String? workingDirectory}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(['build', ...args],
        out: out,
        err: err,
        environment: {'UNODAR_HOME': home, 'PATH': p.join(temp.path, 'empty'), 'HOME': temp.path},
        workingDirectory: workingDirectory ?? temp.path);
    return (exitCode: code, out: '$out', err: '$err');
  }

  FakeArduinoCli managed({Map<String, Object?>? compileResult}) =>
      FakeArduinoCli(p.join(home, 'bin'), compileResult: compileResult);

  const failed = {
    'success': false,
    'compiler_err': "input.dart:6:3: error: 'wdt_enable' was not declared in this scope",
    'error': 'Error during build: exit status 1',
  };

  test('compiles the sketch with -fwrapv into <out>/.build/<name> and prints the sizes, exit 0', () async {
    final fake = managed();
    final r = await build([blink, '-o', 'out']);
    expect(r.exitCode, 0, reason: r.err);
    expect(r.out, '${p.join('out', 'input', 'input.ino')}\nflash 924 B of 32256 (2 %), RAM 9 B of 2048 (0 %)\n');
    final compile = fake.calls.singleWhere((c) => c.startsWith('compile'));
    expect(compile, contains('--fqbn arduino:avr:uno'));
    expect(compile, contains('--build-property compiler.cpp.extra_flags=-fwrapv'));
    expect(compile, contains('--build-property compiler.c.elf.extra_flags=-fwrapv'));
    expect(compile, contains('--build-path ${p.join(temp.path, 'out', '.build', 'input')}'));
    expect(compile, contains(' ${p.join(temp.path, 'out', 'input')} '));
  });

  test('the input defaults to main.dart in the working directory', () async {
    managed();
    final project = Directory(fromPackage('test', '.build_command_scratch'))..createSync();
    addTearDown(() => project.deleteSync(recursive: true));
    File(blink).copySync(p.join(project.path, 'main.dart'));
    final r = await build(['-o', p.join(temp.path, 'out')], workingDirectory: project.path);
    expect(r.exitCode, 0, reason: r.err);
    expect(r.out, startsWith(p.join(temp.path, 'out', 'main', 'main.ino')));
  });

  test('without a toolchain the C++ is still written, then exit 3 naming setup and --cpp-only', () async {
    final r = await build([blink, '-o', 'out']);
    expect(r.exitCode, 3);
    expect(File(p.join(temp.path, 'out', 'input', 'input.ino')).existsSync(), isTrue);
    expect(r.err, contains('Run `unodar setup`'));
    expect(r.err, contains('--cpp-only'));
  });

  test('--cpp-only never looks for the toolchain', () async {
    final r = await build([blink, '--cpp-only', '-o', 'out']);
    expect(r.exitCode, 0, reason: r.err);
    expect(r.out, '${p.join('out', 'input', 'input.ino')}\n');
  });

  test('C++ that fails in a program with its own C++ (cpp()) is the user\'s to fix, exit 1', () async {
    managed(compileResult: failed);
    final r = await build([escapeHatch, '-o', 'out']);
    expect(r.exitCode, 1);
    expect(r.err, contains("error: 'wdt_enable' was not declared"));
    expect(r.err, contains('cpp('));
  });

  test('C++ that fails in a program without its own C++ is a unodar bug, exit 2 with the issue URL', () async {
    managed(compileResult: failed);
    final r = await build([blink, '-o', 'out']);
    expect(r.exitCode, 2);
    expect(r.err, contains('This is a bug in unodar'));
    expect(r.err, contains(issuesUrl));
    expect(r.err, contains(p.join(temp.path, 'out', 'input')), reason: 'the sketch folder to attach');
  });
}
