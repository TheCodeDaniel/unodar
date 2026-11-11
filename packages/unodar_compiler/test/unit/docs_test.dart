import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';
import 'package:unodar_compiler/src/diagnostics/diagnostics.dart';

import '../test_paths.dart';

/// Keeps the docs honest (PRD §9.9 criterion 4):
/// * every registered code has a `## Exxx:` section in docs/DIAGNOSTICS.md with an example diagnostic;
/// * every example there is real: its Dart block is compiled and must print exactly the text block under it;
/// * the complete program at the top of docs/SUBSET.md compiles.
void main() {
  final diagnosticsDoc = File(fromPackage('..', '..', 'docs', 'DIAGNOSTICS.md')).readAsStringSync();
  final subsetDoc = File(fromPackage('..', '..', 'docs', 'SUBSET.md')).readAsStringSync();

  // Examples are compiled from inside this package so that `package:unodar` resolves; the file is always named
  // input.dart, which is the name the documented diagnostics show.
  final scratch = Directory(fromPackage('test', '.docs_tmp'));
  setUpAll(() => scratch.createSync(recursive: true));
  tearDownAll(() => scratch.deleteSync(recursive: true));

  Future<CompileResult> compileSnippet(String name, String dart) async {
    final dir = Directory(p.join(scratch.path, name))..createSync(recursive: true);
    final file = File(p.join(dir.path, 'input.dart'))..writeAsStringSync(dart);
    return Compiler().compile(file.path);
  }

  String sectionOf(DiagnosticCode code) {
    final heading = RegExp('^## ${code.id}: ', multiLine: true);
    final start = diagnosticsDoc.indexOf(heading);
    if (start < 0) return '';
    return diagnosticsDoc.substring(start).split(RegExp(r'^## ', multiLine: true))[1];
  }

  String? block(String markdown, String language) =>
      RegExp('```$language\n(.*?)```', dotAll: true).firstMatch(markdown)?.group(1);

  for (final code in DiagnosticCode.values) {
    test('${code.id} is documented with an example', () {
      final section = sectionOf(code);
      expect(section, isNotEmpty, reason: 'add a "## ${code.id}: …" section to docs/DIAGNOSTICS.md');
      expect(section, contains('error[${code.id}]'), reason: 'the ${code.id} section needs an example diagnostic');
    });

    test('the ${code.id} example prints exactly what docs/DIAGNOSTICS.md shows', () async {
      final section = sectionOf(code);
      final dart = block(section, 'dart');
      final text = block(section, 'text');
      expect(dart, isNotNull, reason: 'the ${code.id} section needs a ```dart example');
      expect(text, isNotNull, reason: 'the ${code.id} section needs a ```text block with the output');
      final result = await compileSnippet(code.id, dart!);
      if (result is! CompileFailure) fail('the ${code.id} example compiled instead of failing: $result');
      expect('${result.diagnostics.map((d) => d.format()).join('\n')}\n', text);
    });
  }

  test('the complete program in docs/SUBSET.md compiles', () async {
    final dart = block(subsetDoc, 'dart');
    expect(dart, isNotNull);
    final result = await compileSnippet('subset', dart!);
    expect(result, isA<CompileSuccess>(), reason: '$result');
  });
}
