/// PRD §9.8 compile check: the generated blink sketch must build with the real Arduino toolchain.
///
/// Requires `arduino-cli` on PATH and the `arduino:avr` core installed. When either is missing this test is
/// SKIPPED WITH A REASON that names the exact install commands; `dart test` prints it. It is never skipped silently.
/// Set UNODAR_REQUIRE_ARDUINO=1 (e.g. in CI) to turn a missing toolchain into a failure instead.
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';

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

void main() {
  final missing = missingToolchain();
  final require = Platform.environment['UNODAR_REQUIRE_ARDUINO'] == '1';
  final skip = missing == null || require ? false : 'SKIPPED: $missing.\n$installHelp';

  test('generated blink sketch compiles for arduino:avr:uno', () async {
    if (missing != null) fail('$missing (UNODAR_REQUIRE_ARDUINO=1).\n$installHelp');

    final result = await Compiler().compile(p.join('test', 'golden', 'blink', 'input.dart'));
    if (result is! CompileSuccess) fail('blink did not compile: $result');

    final sketch = Directory.systemTemp.createTempSync('unodar_arduino_').path;
    addTearDown(() => Directory(sketch).deleteSync(recursive: true));
    final dir = Directory(p.join(sketch, 'blink'))..createSync();
    File(p.join(dir.path, 'blink.ino')).writeAsStringSync(result.cpp);

    final build = await Process.run('arduino-cli', ['compile', '--fqbn', const UnoTarget().fqbn, dir.path]);
    printOnFailure('${build.stdout}\n${build.stderr}');
    expect(build.exitCode, 0, reason: 'arduino-cli compile failed');
    // Surface the size report: PRD §11 sets the blink size budget from this measurement.
    print((build.stdout as String).trim());
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}
