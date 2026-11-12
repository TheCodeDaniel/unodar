/// Shared access to the real Arduino toolchain for tests tagged `arduino`.
///
/// When `arduino-cli`, the `arduino:avr` core, or the Servo library is missing, tests using it are SKIPPED WITH A
/// REASON that names the exact install commands; with UNODAR_REQUIRE_ARDUINO=1 (e.g. in CI) a missing toolchain is a
/// failure instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';

const installHelp = '''
arduino-cli and the arduino:avr core are required for this check. Install with:
  brew install arduino-cli            # macOS; other platforms: https://arduino.github.io/arduino-cli/latest/installation/
  arduino-cli core update-index
  arduino-cli core install arduino:avr
  arduino-cli lib install Servo@1.3.0  # Servo is not part of the core (docs/SUBSET.md "Servo")''';

/// Null when the toolchain is ready; otherwise what is missing.
String? missingToolchain() {
  try {
    final cores = Process.runSync('arduino-cli', ['core', 'list']);
    if (cores.exitCode != 0) return 'arduino-cli failed: ${cores.stderr}';
    final libraries = Process.runSync('arduino-cli', ['lib', 'list']);
    if (libraries.exitCode != 0) return 'arduino-cli failed: ${libraries.stderr}';
    return missingFrom(coreList: cores.stdout as String, libraryList: libraries.stdout as String);
  } on ProcessException {
    return 'arduino-cli is not on PATH';
  }
}

/// What is missing given the output of `arduino-cli core list` and `arduino-cli lib list`, or null.
String? missingFrom({required String coreList, required String libraryList}) {
  if (!coreList.contains('arduino:avr')) return 'the arduino:avr core is not installed';
  if (!RegExp(r'^Servo\s', multiLine: true).hasMatch(libraryList)) return 'the Servo library is not installed';
  return null;
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

/// Writes [cpp] as `<name>/<name>.ino` in a temporary sketch folder and compiles it for the Uno.
Future<ArduinoBuild> compileSketch(String name, String cpp) async {
  final sketch = Directory.systemTemp.createTempSync('unodar_arduino_').path;
  addTearDown(() => Directory(sketch).deleteSync(recursive: true));
  final dir = Directory(p.join(sketch, name))..createSync();
  File(p.join(dir.path, '$name.ino')).writeAsStringSync(cpp);

  final run = await Process.run('arduino-cli', [
    'compile',
    '--fqbn',
    const UnoTarget().fqbn,
    for (final property in const UnoTarget().buildProperties) ...['--build-property', property],
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

/// The `skip:` value for a group that needs the toolchain, and a check that fails when it is required but missing.
({Object skip, void Function() check}) arduinoGate() {
  final missing = missingToolchain();
  final require = Platform.environment['UNODAR_REQUIRE_ARDUINO'] == '1';
  return (
    skip: missing == null || require ? false : 'SKIPPED: $missing.\n$installHelp',
    check: () {
      if (missing != null) fail('$missing (UNODAR_REQUIRE_ARDUINO=1).\n$installHelp');
    },
  );
}
