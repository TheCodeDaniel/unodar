import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';
import 'package:unodar_compiler/src/cli/new_project.dart';
import 'package:unodar_compiler/src/version.dart';

import '../test_paths.dart';

/// The newcomer guides show real programs and real output: FIRST_PROGRAM's programs compile, its error is what the
/// CLI prints, and README's quick start is the block `tool/fresh_machine_test.sh` runs.
void main() {
  String doc(String name) => File(fromPackage('..', '..', 'docs', name)).readAsStringSync();
  List<String> blocks(String text, String language) => [
        for (final match in RegExp('```$language\\n(.*?)```', dotAll: true).allMatches(text)) match.group(1)!,
      ];

  final scratch = Directory(fromPackage('test', '.guides_scratch'));
  setUpAll(() => scratch.createSync(recursive: true));
  tearDownAll(() => scratch.deleteSync(recursive: true));

  Future<({int exitCode, String err})> build(String dart) async {
    final file = File(p.join(scratch.path, 'main.dart'))..writeAsStringSync(dart);
    final err = StringBuffer();
    final code = await runCli(['build', file.path, '--cpp-only', '-o', p.join(scratch.path, 'out')],
        out: StringBuffer(), err: err);
    return (exitCode: code, err: '$err');
  }

  final firstProgram = doc('FIRST_PROGRAM.md');
  final programs = blocks(firstProgram, 'dart');

  test('FIRST_PROGRAM shows the template of `unodar new` without its comments', () {
    expect(programs.first,
        newProjectMain.split('\n').where((l) => !l.startsWith('//')).join('\n').replaceFirst('\n\n\n', '\n\n'));
  });

  test('the button program compiles', () async {
    final r = await build(programs[1]);
    expect(r.exitCode, 0, reason: r.err);
  });

  test('the print mistake gives exactly the error the guide shows (at the release tag)', () async {
    final r = await build(programs[1].replaceFirst('led.toggle();', "print('pressed');"));
    expect(r.exitCode, 1);
    final shown = blocks(firstProgram, 'text').singleWhere((b) => b.contains('error[E003]'));
    expect(r.err.replaceAll('v$unodarVersion', 'v0.7.0'), startsWith(shown));
  });

  test("README's quick start creates a project and flashes it, in that order", () {
    final readme = File(fromPackage('..', '..', 'README.md')).readAsStringSync();
    final start = readme.indexOf('<!-- quickstart -->');
    final end = readme.indexOf('<!-- /quickstart -->');
    expect(start, greaterThan(0));
    final quickstart = blocks(readme.substring(start, end), 'sh').single;
    expect(quickstart.split('\n').where((l) => l.isNotEmpty).toList(), [
      'dart pub global activate --source git https://github.com/TheCodeDaniel/unodar \\',
      '  --git-path packages/unodar_compiler --git-ref v0.7.0',
      'unodar setup',
      'unodar new hello',
      'cd hello',
      'unodar flash',
    ]);
  });

  test('the minimum Dart SDK is the same in pubspec.lock, the CI job and the README', () {
    final lock = File(fromPackage('..', '..', 'pubspec.lock')).readAsStringSync();
    final minimum = RegExp(r'dart: ">=(\d+\.\d+)\.(\d+) <').firstMatch(lock)!;
    final ci = File(fromPackage('..', '..', '.github', 'workflows', 'ci.yml')).readAsStringSync();
    expect(ci, contains('minimum-sdk:'));
    expect(ci, contains('sdk: ${minimum.group(1)}.${minimum.group(2)}\n'));
    final readme = File(fromPackage('..', '..', 'README.md')).readAsStringSync();
    expect(readme, contains('Dart SDK](https://dart.dev/get-dart) ${minimum.group(1)} or later'));
  });

  test('the fresh-machine CI job runs tool/fresh_machine_test.sh on macOS and Linux', () {
    final ci = File(fromPackage('..', '..', '.github', 'workflows', 'ci.yml')).readAsStringSync();
    expect(ci, contains('os: [ubuntu-latest, macos-latest]'));
    expect(ci, contains('run: tool/fresh_machine_test.sh'));
  });
}
