import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/cli/cli.dart';
import 'package:unodar_compiler/src/cli/new_project.dart';
import 'package:unodar_compiler/src/version.dart';

import '../test_paths.dart';

/// `unodar new`, and the version match between a project's package:unodar and the compiler (D7).
void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('unodar_new_test_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<({int exitCode, String out, String err})> run(List<String> args, {String? workingDirectory}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(args,
        out: out,
        err: err,
        environment: {'UNODAR_HOME': p.join(temp.path, 'home'), 'PATH': '', 'HOME': temp.path},
        workingDirectory: workingDirectory ?? temp.path);
    return (exitCode: code, out: '$out', err: '$err');
  }

  test('the template main.dart is the new_project golden, verbatim', () {
    expect(newProjectMain, File(fromPackage('test', 'golden', 'new_project', 'input.dart')).readAsStringSync());
  });

  test('a new project depends on package:unodar at the release tag of this compiler', () {
    final pubspec = newProjectPubspec('hello');
    expect(pubspec, contains('name: hello\n'));
    expect(pubspec, contains('      url: https://github.com/TheCodeDaniel/unodar\n'));
    expect(pubspec, contains('      path: packages/unodar\n'));
    expect(pubspec, contains('      ref: v$unodarVersion\n'));
  });

  test('new writes the project and says what to run next, exit 0', () async {
    final r = await run(['new', 'hello', '--no-pub']);
    expect(r.exitCode, 0, reason: r.err);
    final dir = p.join(temp.path, 'hello');
    expect(Directory(dir).listSync().map((e) => p.basename(e.path)).toSet(),
        {'pubspec.yaml', 'main.dart', 'README.md', '.gitignore'});
    expect(File(p.join(dir, 'main.dart')).readAsStringSync(), newProjectMain);
    expect(r.out, contains('  cd hello\n  unodar flash'));
  });

  test('a project made with pub get builds with this compiler (package:unodar from the checkout)', () async {
    final scratch = Directory(p.join(temp.path, 'projects'))..createSync();
    final r =
        await run(['new', 'blinky', '--unodar-path', fromPackage('..', 'unodar')], workingDirectory: scratch.path);
    expect(r.exitCode, 0, reason: '${r.out}\n${r.err}');
    final project = p.join(scratch.path, 'blinky');
    final built = await run(['build', '--cpp-only'], workingDirectory: project);
    expect(built.exitCode, 0, reason: built.err);
    expect(File(p.join(project, 'build', 'main', 'main.ino')).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a name that is not a Dart package name is refused, exit 2', () async {
    for (final name in ['Hello', 'my-project', '2fast', 'class']) {
      final r = await run(['new', name, '--no-pub']);
      expect(r.exitCode, 2, reason: name);
      expect(r.err, contains('cannot be a project name'));
    }
  });

  test('a non-empty folder is never overwritten, exit 2', () async {
    File(p.join(temp.path, 'taken', 'notes.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    final r = await run(['new', 'taken', '--no-pub']);
    expect(r.exitCode, 2);
    expect(r.err, contains('already exists and is not empty'));
    expect(File(p.join(temp.path, 'taken', 'notes.txt')).readAsStringSync(), 'mine');
    expect(File(p.join(temp.path, 'taken', 'main.dart')).existsSync(), isFalse);
  });

  group('version match (D7)', () {
    /// A project whose package_config points at a package:unodar with [version].
    String projectWith(String version) {
      final project = p.join(temp.path, 'old_project');
      final unodar = p.join(temp.path, 'unodar_$version');
      File(p.join(unodar, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: unodar\nversion: $version\n');
      File(p.join(project, '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'unodar', 'rootUri': p.toUri(unodar).toString(), 'packageUri': 'lib/'},
          ],
        }));
      File(p.join(project, 'main.dart')).writeAsStringSync(newProjectMain);
      return project;
    }

    test('build refuses a project on another unodar version, exit 3, with both fixes', () async {
      final project = projectWith('0.6.0');
      final r = await run(['build', '--cpp-only'], workingDirectory: project);
      expect(r.exitCode, 3);
      expect(r.err, contains('uses package:unodar 0.6.0, but this compiler is unodar $unodarVersion'));
      expect(r.err, contains('ref:'));
      expect(r.err, contains('--git-ref v0.6.0'));
      expect(Directory(p.join(project, 'build')).existsSync(), isFalse);
    });

    test('doctor reports the mismatch as a problem', () async {
      final project = projectWith('0.6.0');
      final r = await run(['doctor'], workingDirectory: project);
      expect(r.exitCode, 3);
      expect(r.out, contains('✗ project $project uses unodar 0.6.0, but this compiler is $unodarVersion'));
    });

    test('doctor confirms a matching project', () async {
      final r = await run(['doctor'], workingDirectory: fromPackage('..', '..'));
      expect(r.out, contains('uses unodar $unodarVersion (matches this compiler)'));
    });
  });
}
