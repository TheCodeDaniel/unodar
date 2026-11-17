import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';
import 'package:unodar_compiler/src/cli/render.dart';
import 'package:unodar_compiler/src/diagnostics/diagnostics.dart';
import 'package:unodar_compiler/src/version.dart';

import '../test_paths.dart';

/// How the CLI shows a diagnostic (D8): source line, caret and link in the terminal; `--plain` and the goldens keep
/// `Diagnostic.format()`.
void main() {
  /// GitHub's heading anchor: lower case, punctuation other than `-` and `_` removed, spaces to `-`.
  String githubAnchor(String heading) => heading.toLowerCase().replaceAll(RegExp(r'[^\w\- ]'), '').replaceAll(' ', '-');

  test('every code links to its own section of DIAGNOSTICS.md', () {
    final headings = {
      for (final line in File(fromPackage('..', '..', 'docs', 'DIAGNOSTICS.md')).readAsLinesSync())
        if (RegExp(r'^## (E\d{3}):').firstMatch(line) case final match?)
          match.group(1)!: githubAnchor(line.substring(3)),
    };
    expect(diagnosticAnchors, headings);
    expect(DiagnosticCode.values.map((c) => c.id).toSet(), diagnosticAnchors.keys.toSet());
    expect(diagnosticLink(DiagnosticCode.unsupportedArgument),
        'https://github.com/TheCodeDaniel/unodar/blob/v$unodarVersion/docs/DIAGNOSTICS.md#e004-unsupported-argument');
  });

  const diagnostic = Diagnostic(
    code: DiagnosticCode.unsupportedArgument,
    location: SourceLocation(file: 'main.dart', line: 8, column: 16),
    message: 'argument -13 is out of range for parameter \'pin\' of digitalWrite, which is a uint8_t (0 to 255).',
    suggestion: 'Pass a value from 0 to 255.',
  );
  final source = '${List.generate(7, (i) => '// line ${i + 1}').join('\n')}\n  digitalWrite(-13, HIGH);\n}\n';

  test('the source line with a caret under the column, the help, and the link', () {
    expect(
        renderDiagnostic(diagnostic, source: source),
        'main.dart:8:16: error[E004]: argument -13 is out of range for parameter \'pin\' of digitalWrite, which is a '
        'uint8_t (0 to 255).\n'
        '  |\n'
        '8 |   digitalWrite(-13, HIGH);\n'
        '  |                ^\n'
        '  = help: Pass a value from 0 to 255.\n'
        '  = see: ${diagnosticLink(DiagnosticCode.unsupportedArgument)}');
  });

  test('without the source there is no snippet; colour only when asked', () {
    expect(renderDiagnostic(diagnostic), isNot(contains(' |')));
    expect(renderDiagnostic(diagnostic, source: source), isNot(contains('\x1B[')));
    expect(renderDiagnostic(diagnostic, source: source, color: true), contains('\x1B[1;31merror[E004]\x1B[0m'));
  });

  group('the CLI', () {
    final input = fromPackage('test', 'golden', 'e004_argument_out_of_range', 'input.dart');

    Future<String> stderrOf(List<String> args, {bool color = false, Map<String, String>? environment}) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final temp = Directory.systemTemp.createTempSync('unodar_render_');
      addTearDown(() => temp.deleteSync(recursive: true));
      await runCli(['build', input, '--cpp-only', '-o', temp.path, ...args],
          out: out, err: err, color: color, environment: environment ?? const {});
      return '$err';
    }

    test('shows snippets and links by default', () async {
      final err = await stderrOf([]);
      expect(err, contains('8 |   digitalWrite(-13, HIGH);\n'));
      expect(err, contains('  = see: ${diagnosticLink(DiagnosticCode.unsupportedArgument)}'));
      expect(err, endsWith('2 errors.\n'));
    });

    test('--plain is exactly the golden format', () async {
      final err = await stderrOf(['--plain']);
      expect(err,
          '${File(fromPackage('test', 'golden', 'e004_argument_out_of_range', 'expected_errors.txt')).readAsStringSync()}2 errors.\n');
    });

    test('colour on a terminal, never with NO_COLOR', () async {
      expect(await stderrOf([], color: true), contains('\x1B['));
      expect(await stderrOf([], color: true, environment: {'NO_COLOR': '1'}), isNot(contains('\x1B[')));
    });
  });
}
