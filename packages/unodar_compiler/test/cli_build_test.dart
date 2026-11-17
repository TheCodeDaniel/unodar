/// `unodar build` with the real toolchain: the size it prints is the one the budgets record, and C++ of the user's
/// own that fails points at the Dart file.
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';

import 'arduino_toolchain.dart';
import 'size_budgets.dart';
import 'test_paths.dart';

void main() {
  final gate = arduinoGate();
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('unodar_cli_build_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<({int exitCode, String out, String err})> build(String input) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(['build', input, '-o', temp.path], out: out, err: err);
    return (exitCode: code, out: '$out', err: '$err');
  }

  test('blink builds and reports the size its budget records', () async {
    gate.check();
    final r = await build(fromPackage('test', 'golden', 'blink', 'input.dart'));
    expect(r.exitCode, 0, reason: r.err);
    final budget = sizeBudgets['blink']!;
    expect(
        r.out.split('\n')[1],
        'flash ${budget.baselineFlash} B of 32256 (${budget.baselineFlash * 100 ~/ 32256} %), '
        'RAM ${budget.baselineRam} B of 2048 (${budget.baselineRam * 100 ~/ 2048} %)');
    expect(File(p.join(temp.path, '.build', 'input', 'input.ino.hex')).existsSync(), isTrue,
        reason: 'flash uploads this build');
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 2)));

  test('a cpp() statement that does not compile is exit 1, located in the Dart file', () async {
    gate.check();
    final scratch = Directory(fromPackage('test', '.cli_build_scratch'))..createSync();
    addTearDown(() => scratch.deleteSync(recursive: true));
    final input = File(p.join(scratch.path, 'main.dart'))
      ..writeAsStringSync("import 'package:unodar/unodar.dart';\n\nvoid setup() {}\n\nvoid loop() {\n"
          "  cpp('undeclaredFunction();');\n}\n");
    final r = await build(input.path);
    expect(r.exitCode, 1, reason: r.err);
    expect(r.err, contains('main.dart:6'), reason: '#line points the C++ error at the cpp() statement');
    expect(r.err, contains('undeclaredFunction'));
    expect(r.err, contains('C++ of its own'));
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 2)));
}
