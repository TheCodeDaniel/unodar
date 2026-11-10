/// Checks against the real Arduino toolchain (PRD §9.8 compile check, PRD §11 size budgets).
///
/// Requires `arduino-cli` on PATH and the `arduino:avr` core installed. When either is missing these tests are
/// SKIPPED WITH A REASON that names the exact install commands; `dart test` prints it. They are never skipped
/// silently. Set UNODAR_REQUIRE_ARDUINO=1 (e.g. in CI) to turn a missing toolchain into a failure instead.
@Tags(['arduino'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';

import 'size_budgets.dart';
import 'test_paths.dart';

const installHelp = '''
arduino-cli and the arduino:avr core are required for this check. Install with:
  brew install arduino-cli            # macOS; other platforms: https://arduino.github.io/arduino-cli/latest/installation/
  arduino-cli core update-index
  arduino-cli core install arduino:avr''';

/// Null when the toolchain is ready; otherwise what is missing.
String? missingToolchain() {
  try {
    final cores = Process.runSync('arduino-cli', ['core', 'list']);
    if (cores.exitCode != 0) return 'arduino-cli failed: ${cores.stderr}';
    if (!(cores.stdout as String).contains('arduino:avr')) return 'the arduino:avr core is not installed';
    return null;
  } on ProcessException {
    return 'arduino-cli is not on PATH';
  }
}

/// The outcome of `arduino-cli compile --format json` for one golden case.
final class ArduinoBuild {
  ArduinoBuild(this.exitCode, this.json, this.rawOutput);

  final int exitCode;
  final Map<String, Object?>? json;
  final String rawOutput;

  bool get success => exitCode == 0 && json?['success'] == true;

  /// Size of an ELF section as reported by arduino-cli: `text` = flash, `data` = RAM.
  int section(String name) {
    final result = json?['builder_result'] as Map<String, Object?>?;
    final sections = (result?['executable_sections_size'] as List<Object?>?)?.cast<Map<String, Object?>>();
    final entry = sections?.where((s) => s['name'] == name).firstOrNull;
    if (entry == null) throw StateError('arduino-cli reported no "$name" section:\n$rawOutput');
    return entry['size']! as int;
  }
}

/// Compiles `test/golden/<goldenCase>` with unodar, then with arduino-cli for the Uno.
Future<ArduinoBuild> buildGolden(String goldenCase) async {
  final result = await Compiler().compile(fromPackage('test', 'golden', goldenCase, 'input.dart'));
  if (result is! CompileSuccess) fail('$goldenCase did not compile with unodar: $result');

  final sketch = Directory.systemTemp.createTempSync('unodar_arduino_').path;
  addTearDown(() => Directory(sketch).deleteSync(recursive: true));
  final dir = Directory(p.join(sketch, goldenCase))..createSync();
  File(p.join(dir.path, '$goldenCase.ino')).writeAsStringSync(result.cpp);

  final run = await Process.run('arduino-cli', [
    'compile',
    '--fqbn',
    const UnoTarget().fqbn,
    '--format',
    'json',
    dir.path,
  ]);
  final output = '${run.stdout}\n${run.stderr}';
  Map<String, Object?>? json;
  try {
    json = jsonDecode(run.stdout as String) as Map<String, Object?>;
  } on FormatException {
    json = null;
  }
  return ArduinoBuild(run.exitCode, json, output);
}

void main() {
  final missing = missingToolchain();
  final require = Platform.environment['UNODAR_REQUIRE_ARDUINO'] == '1';
  final skip = missing == null || require ? false : 'SKIPPED: $missing.\n$installHelp';

  void checkToolchain() {
    if (missing != null) fail('$missing (UNODAR_REQUIRE_ARDUINO=1).\n$installHelp');
  }

  group('arduino:avr:uno', () {
    // One arduino-cli build per case, shared by the compile and budget tests (a build takes seconds).
    final builds = <String, Future<ArduinoBuild>>{};
    Future<ArduinoBuild> build(String goldenCase) => builds.putIfAbsent(goldenCase, () => buildGolden(goldenCase));

    test('generated blink sketch compiles', () async {
      checkToolchain();
      final result = await build('blink');
      printOnFailure(result.rawOutput);
      expect(result.success, isTrue, reason: 'arduino-cli compile failed');
    });

    for (final MapEntry(key: goldenCase, value: budget) in sizeBudgets.entries) {
      test('$goldenCase stays within its size budget', () async {
        checkToolchain();
        final result = await build(goldenCase);
        printOnFailure(result.rawOutput);
        expect(result.success, isTrue, reason: 'arduino-cli compile failed');

        final flash = result.section('text');
        final ram = result.section('data');
        print(
          '$goldenCase: flash $flash B (baseline ${budget.baselineFlash}, max ${budget.maxFlash}), '
          'RAM $ram B (baseline ${budget.baselineRam}, max ${budget.maxRam})',
        );
        const policy = 'See test/size_budgets.dart: find the cause before changing a budget.';
        expect(flash, lessThanOrEqualTo(budget.maxFlash), reason: '$goldenCase flash over budget. $policy');
        expect(ram, lessThanOrEqualTo(budget.maxRam), reason: '$goldenCase RAM over budget. $policy');
      });
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
