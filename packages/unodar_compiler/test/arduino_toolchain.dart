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

import 'test_paths.dart';

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
  ArduinoBuild(this.exitCode, this.json, this.rawOutput, {required this.name});

  final int exitCode;
  final Map<String, Object?>? json;
  final String rawOutput;

  /// The sketch name; the linked program is `<build path>/<name>.ino.elf`.
  final String name;

  Map<String, Object?>? get _builder => json?['builder_result'] as Map<String, Object?>?;

  /// The Intel HEX image arduino-cli produced (what an upload would write to flash).
  String get hexPath => p.join(_builder!['build_path']! as String, '$name.ino.hex');

  /// The heap functions the linked program contains (PRD §11 "no heap"), read from its symbol table with the
  /// core's own `avr-nm`. Empty means nothing in the sketch, the core, or a library calls the allocator: avr-libc's
  /// malloc is only linked in when something references it.
  List<String> heapSymbols() {
    final properties = [...(_builder?['build_properties'] as List<Object?>? ?? const []).cast<String>()];
    final compilerPath = properties
        .firstWhere((p) => p.startsWith('compiler.path='), orElse: () => throw StateError('no compiler.path'))
        .substring('compiler.path='.length);
    final elf = p.join(_builder!['build_path']! as String, '$name.ino.elf');
    final nm = Process.runSync(p.join(compilerPath, 'avr-nm'), ['-C', elf]);
    if (nm.exitCode != 0) throw StateError('avr-nm failed on $elf: ${nm.stderr}');
    return [
      for (final line in (nm.stdout as String).split('\n'))
        if (heapSymbol.firstMatch(line) case final match?) match.group(1)!,
    ];
  }

  /// Defined or referenced allocator symbols in `avr-nm -C` output.
  static final heapSymbol =
      RegExp(r'\s(malloc|calloc|realloc|free|operator new(?:\[\])?\(.*\)|operator delete(?:\[\])?\(.*\))$');

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

/// Writes [cpp] as `<name>/<name>.ino` in a temporary sketch folder, plus [files] (file name to contents, e.g. the
/// widget runtime header) next to it, and compiles it for the Uno, with [buildProperties] (default: the target's,
/// i.e. -fwrapv; the runtime harness's negative control passes none).
Future<ArduinoBuild> compileSketch(String name, String cpp,
    {Map<String, String> files = const {}, List<String>? buildProperties}) async {
  final sketch = Directory.systemTemp.createTempSync('unodar_arduino_').path;
  addTearDown(() => Directory(sketch).deleteSync(recursive: true));
  final dir = Directory(p.join(sketch, name))..createSync();
  File(p.join(dir.path, '$name.ino')).writeAsStringSync(cpp);
  for (final MapEntry(key: fileName, value: contents) in files.entries) {
    File(p.join(dir.path, fileName)).writeAsStringSync(contents);
  }

  final run = await Process.run('arduino-cli', [
    'compile',
    '--fqbn',
    const UnoTarget().fqbn,
    for (final property in buildProperties ?? const UnoTarget().buildProperties) ...['--build-property', property],
    // Inside the temporary sketch folder, so the .elf is ours to inspect and is removed with it.
    '--build-path',
    p.join(sketch, 'build'),
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
  return ArduinoBuild(run.exitCode, json, output, name: name);
}

/// The avr8js runner (docs/DECISIONS.md "runtime fidelity harness").
final String avrRunner = p.join(packageRoot, '..', '..', 'tool', 'avr_runner', 'run.mjs');

const nodeHelp = '''
The runtime fidelity harness runs programs in avr8js, which needs Node.js 20.19 or later. Install with:
  brew install node                   # macOS; other platforms: https://nodejs.org/
  (cd tool/avr_runner && npm ci)      # installs the pinned avr8js from package-lock.json''';

/// Null when Node.js and the runner's pinned avr8js are installed; otherwise what is missing.
String? missingRunner() {
  try {
    final node = Process.runSync('node', ['--version']);
    if (node.exitCode != 0) return 'node failed: ${node.stderr}';
  } on ProcessException {
    return 'node (Node.js) is not on PATH';
  }
  final installed = File(p.join(p.dirname(avrRunner), 'node_modules', 'avr8js', 'package.json'));
  if (!installed.existsSync()) return 'avr8js is not installed in tool/avr_runner (run `npm ci` there)';
  return null;
}

/// Runs [hexPath] in avr8js until it prints [until] (or the runner's cycle limit), with ADC channel voltages
/// [adc] (`{0: 5.0}` sets A0 to 5 V). Returns what the program sent on the serial port.
Future<String> runInSimulator(String hexPath, {Map<int, double> adc = const {}, String until = 'DONE'}) async =>
    (await simulate(hexPath, adc: adc, until: until)).serial;

/// Like [runInSimulator], and also drives input pins and records every pin's state changes.
///
/// [pins] are the runner's `--pin` values, e.g. `D2=low@100` (drive D2 LOW from 100 ms of simulated time on) and
/// `D2=open@180` (release it). [cycles] overrides the runner's limit (default two simulated seconds); with
/// [until] null the program runs to that limit. The result's `pinLog` holds the runner's `<ms> <pin> <state>` lines.
Future<({String serial, List<String> pinLog})> simulate(String hexPath,
    {Map<int, double> adc = const {}, List<String> pins = const [], String? until = 'DONE', int? cycles}) async {
  final dir = Directory.systemTemp.createTempSync('unodar_avr_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final logPath = p.join(dir.path, 'pins.log');
  final run = await Process.run('node', [
    avrRunner,
    hexPath,
    if (until != null) ...['--until', until],
    if (cycles != null) ...['--cycles', '$cycles'],
    for (final MapEntry(:key, :value) in adc.entries) ...['--adc', 'A$key=$value'],
    for (final pin in pins) ...['--pin', pin],
    '--pin-log',
    logPath,
  ]);
  if (run.exitCode != 0) fail('avr_runner exited with ${run.exitCode}:\n${run.stdout}\n${run.stderr}');
  final log = File(logPath).readAsLinesSync();
  return (serial: run.stdout as String, pinLog: log);
}

/// [arduinoGate] for tests that also run programs in avr8js.
({Object skip, void Function() check}) simulatorGate() {
  final arduino = arduinoGate();
  final missing = missingRunner();
  final require = Platform.environment['UNODAR_REQUIRE_ARDUINO'] == '1';
  return (
    skip: arduino.skip != false ? arduino.skip : (missing == null || require ? false : 'SKIPPED: $missing.\n$nodeHelp'),
    check: () {
      arduino.check();
      if (missing != null) fail('$missing (UNODAR_REQUIRE_ARDUINO=1).\n$nodeHelp');
    },
  );
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
