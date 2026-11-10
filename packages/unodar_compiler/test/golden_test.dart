/// Golden tests (PRD §9.8). Each directory under `test/golden/` is one case:
///
///   input.dart            the Dart source given to the compiler
///   expected.ino          expected C++ for cases that compile, or
///   expected_errors.txt   expected diagnostics, one formatted diagnostic per entry, for cases that must fail
///
/// To deliberately accept new output, run with `UPDATE_GOLDENS=1` and review the diff before committing:
///
///   UPDATE_GOLDENS=1 dart test test/golden_test.dart
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';

final bool updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  final root = Directory(p.join('test', 'golden'));
  final cases = root.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  final compiler = Compiler();

  test('golden directory is not empty', () => expect(cases, isNotEmpty));

  for (final dir in cases) {
    test(p.basename(dir.path), () async {
      final input = p.join(dir.path, 'input.dart');
      final expectedIno = File(p.join(dir.path, 'expected.ino'));
      final expectedErrors = File(p.join(dir.path, 'expected_errors.txt'));

      final result = await compiler.compile(input);
      final (actualFile, staleFile, actual) = switch (result) {
        CompileSuccess(:final cpp) => (expectedIno, expectedErrors, cpp),
        CompileFailure(:final diagnostics) => (
            expectedErrors,
            expectedIno,
            '${diagnostics.map((d) => d.format()).join('\n')}\n',
          ),
        CompileInputError(:final message) => fail('input error in golden case: $message'),
      };

      if (updateGoldens) {
        actualFile.writeAsStringSync(actual);
        if (staleFile.existsSync()) staleFile.deleteSync();
        return;
      }
      if (!actualFile.existsSync()) {
        fail(
          'expected ${p.basename(staleFile.path)} behaviour, but the compiler produced '
          '${p.basename(actualFile.path)}:\n$actual',
        );
      }
      expect(actual, actualFile.readAsStringSync());
    });
  }
}
