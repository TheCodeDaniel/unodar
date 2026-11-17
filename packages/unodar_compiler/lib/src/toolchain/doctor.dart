import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../version.dart';
import 'pins.dart';
import 'project.dart';
import 'toolchain.dart';

/// How a doctor line counts.
enum CheckStatus {
  /// Fine.
  ok('✓'),

  /// Something a command will need is missing or wrong; `doctor` exits with 3.
  problem('✗'),

  /// Worth knowing, but nothing fails because of it yet (e.g. no permission for serial ports before uploading).
  warning('!'),

  /// Information only.
  info('·');

  const CheckStatus(this.symbol);

  final String symbol;
}

/// One line of `unodar doctor`, with the exact command that fixes a problem or warning.
final class DoctorCheck {
  const DoctorCheck(this.status, this.text, {this.fix});

  final CheckStatus status;
  final String text;
  final String? fix;
}

/// What `unodar doctor` checks (PRD §8.1). [dev] adds what contributors need: Node and the avr8js runner in
/// [checkout], the repo folder (null when doctor runs outside one).
List<DoctorCheck> runDoctor({
  required UnodarHome home,
  required Map<String, String> environment,
  bool dev = false,
  String? checkout,
  ToolchainPins? pins,
  String? project,
}) {
  pins ??= ToolchainPins.embedded;
  final checks = <DoctorCheck>[];
  final managed = managedCli(home);
  final onPath = pathCli(environment);
  ArduinoCli? used;
  ToolchainInventory? inventory;

  if (managed != null) {
    try {
      final managedInventory = ToolchainInventory.read(managed);
      used = managed;
      inventory = managedInventory;
      checks.add(managedInventory.cliVersion == pins.cliVersion
          ? DoctorCheck(CheckStatus.ok, 'arduino-cli ${managedInventory.cliVersion} (${_tilde(managed.executable)})')
          : DoctorCheck(CheckStatus.problem,
              'arduino-cli ${managedInventory.cliVersion} in ${_tilde(home.path)}, but unodar needs ${pins.cliVersion}',
              fix: 'unodar setup'));
    } on ToolchainException catch (e) {
      checks.add(
          DoctorCheck(CheckStatus.problem, 'arduino-cli in ${_tilde(home.path)}: ${e.message}', fix: 'unodar setup'));
    }
  } else if (onPath != null) {
    try {
      inventory = ToolchainInventory.read(onPath);
      used = onPath;
      checks.add(DoctorCheck(
          CheckStatus.ok,
          'arduino-cli ${inventory.cliVersion} on PATH (${onPath.executable}); no managed toolchain in '
          '${_tilde(home.path)}'));
    } on ToolchainException catch (e) {
      checks.add(DoctorCheck(CheckStatus.problem, 'arduino-cli on PATH: ${e.message}', fix: 'unodar setup'));
    }
  } else {
    checks.add(DoctorCheck(CheckStatus.problem, 'arduino-cli: not installed', fix: 'unodar setup'));
  }

  if (inventory != null) {
    final core = inventory.cores[pins.core.name];
    checks.add(core == pins.core.version
        ? DoctorCheck(CheckStatus.ok, 'core ${pins.core.name} $core')
        : DoctorCheck(CheckStatus.problem,
            'core ${pins.core.name}: ${core == null ? 'not installed' : '$core, but unodar needs ${pins.core.version}'}',
            fix: 'unodar setup'));
    for (final library in pins.libraries) {
      final installed = inventory.libraries[library.name];
      checks.add(installed == library.version
          ? DoctorCheck(CheckStatus.ok, 'library ${library.name} $installed')
          : DoctorCheck(
              CheckStatus.problem,
              'library ${library.name}: '
              '${installed == null ? 'not installed' : '$installed, but unodar needs ${library.version}'}',
              fix: 'unodar setup'));
    }
    if (core != null && used != null) checks.add(_compilerRuns(used, home));
  } else {
    checks.add(DoctorCheck(
        CheckStatus.problem, 'core ${pins.core.name} and the libraries: not checked (no arduino-cli)',
        fix: 'unodar setup'));
  }

  if (project != null) {
    if (resolvedUnodar(project) case (:final version, project: final root)) {
      final problem = unodarVersionProblem(project);
      checks.add(problem == null
          ? DoctorCheck(CheckStatus.ok, 'project $root uses unodar $version (matches this compiler)')
          : DoctorCheck(CheckStatus.problem, 'project $root uses unodar $version, but this compiler is $unodarVersion',
              fix: 'change the unodar `ref:` in pubspec.yaml to v$unodarVersion and run `dart pub get`'));
    }
  }
  if (Platform.isLinux) checks.add(_serialPermission(environment));
  if (managed != null && onPath != null) {
    checks.add(DoctorCheck(CheckStatus.info, 'arduino-cli on PATH (${onPath.executable}): not used'));
  }
  if (used != null) checks.add(_boards(used));
  if (dev) checks.addAll(_devChecks(checkout, environment));
  return checks;
}

/// The core's avr-gcc runs. On an Apple Silicon Mac the arduino:avr toolchain may be built for Intel only, and then
/// needs Rosetta 2.
DoctorCheck _compilerRuns(ArduinoCli cli, UnodarHome home) {
  final data = cli.managed ? home.dataDirectory : _configuredDataDirectory(cli);
  final tools = Directory(p.join(data ?? '', 'packages', 'arduino', 'tools', 'avr-gcc'));
  final compilers = tools.existsSync()
      ? [
          for (final dir in tools.listSync().whereType<Directory>())
            if (File(p.join(dir.path, 'bin', 'avr-gcc')).existsSync()) p.join(dir.path, 'bin', 'avr-gcc')
        ]
      : <String>[];
  if (compilers.isEmpty) {
    return const DoctorCheck(CheckStatus.problem, 'avr-gcc (the C++ compiler of the core): not found',
        fix: 'unodar setup');
  }
  compilers.sort();
  final gcc = compilers.last;
  try {
    final run = Process.runSync(gcc, ['--version']);
    if (run.exitCode == 0) {
      final first = LineSplitter.split('${run.stdout}').firstOrNull ?? 'avr-gcc';
      return DoctorCheck(CheckStatus.ok, '$first runs');
    }
    return DoctorCheck(CheckStatus.problem, 'avr-gcc fails: ${'${run.stderr}'.trim()}', fix: 'unodar setup');
  } on ProcessException catch (e) {
    final rosetta = Platform.isMacOS && (e.errorCode == 86 || e.message.contains('Bad CPU type'));
    return DoctorCheck(
        CheckStatus.problem,
        rosetta
            ? 'avr-gcc is built for Intel Macs and needs Rosetta 2, which is not installed'
            : 'avr-gcc cannot run: ${e.message}',
        fix: rosetta ? 'softwareupdate --install-rosetta --agree-to-license' : 'unodar setup');
  }
}

String? _configuredDataDirectory(ArduinoCli cli) {
  try {
    final run = cli.runSync(['config', 'get', 'directories.data']);
    return run.exitCode == 0 ? '${run.stdout}'.trim() : null;
  } on ProcessException {
    return null;
  }
}

/// On Linux, opening `/dev/ttyACM0` needs the `dialout` group (`uucp` on Arch). Checked from `id -nG`.
DoctorCheck _serialPermission(Map<String, String> environment) {
  try {
    final groups = '${Process.runSync('id', ['-nG']).stdout}'.split(RegExp(r'\s+'));
    if (groups.contains('dialout') || groups.contains('uucp') || groups.contains('root')) {
      return const DoctorCheck(CheckStatus.ok, 'serial ports: allowed (group dialout)');
    }
  } on ProcessException {
    // Fall through: report it as unknown.
  }
  return const DoctorCheck(
      CheckStatus.warning, 'serial ports: you are not in the dialout group, so uploading will be refused',
      fix: r'sudo usermod -aG dialout $USER   (then log out and in again)');
}

/// The boards plugged in, for information. Port choice itself is `unodar flash`'s.
DoctorCheck _boards(ArduinoCli cli) {
  try {
    final run = cli.runSync(['board', 'list', '--format', 'json']);
    if (run.exitCode != 0) return const DoctorCheck(CheckStatus.info, 'boards: could not be listed');
    final json = jsonDecode('${run.stdout}') as Map<String, Object?>;
    final unos = [
      for (final port in (json['detected_ports'] as List<Object?>? ?? const []).cast<Map<String, Object?>>())
        if ((port['matching_boards'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>()
            .any((b) => b['fqbn'] == 'arduino:avr:uno'))
          (port['port'] as Map<String, Object?>?)?['address'],
    ].whereType<String>();
    return DoctorCheck(
        CheckStatus.info, unos.isEmpty ? 'boards: no Uno plugged in' : 'boards: Uno on ${unos.join(', ')}');
  } on Object {
    return const DoctorCheck(CheckStatus.info, 'boards: could not be listed');
  }
}

/// Node (for the avr8js runner of the runtime tests) and the runner's pinned packages.
List<DoctorCheck> _devChecks(String? checkout, Map<String, String> environment) {
  if (checkout == null) {
    return const [
      DoctorCheck(CheckStatus.problem, '--dev: not inside a unodar checkout (no tool/avr_runner/package-lock.json)',
          fix: 'cd into your clone of github.com/TheCodeDaniel/unodar')
    ];
  }
  final checks = <DoctorCheck>[];
  final node = nodeVersion();
  checks.add(switch (node) {
    null => const DoctorCheck(CheckStatus.problem, 'Node.js: not installed (the runtime tests need 20.19 or later)',
        fix: 'brew install node   (or https://nodejs.org/)'),
    final v when !_atLeast(v, const [20, 19]) => DoctorCheck(
        CheckStatus.problem, 'Node.js $v, but the runtime tests need 20.19 or later',
        fix: 'brew upgrade node   (or https://nodejs.org/)'),
    final v => DoctorCheck(CheckStatus.ok, 'Node.js $v'),
  });
  checks.add(avrRunnerInstalled(checkout)
      ? const DoctorCheck(CheckStatus.ok, 'tool/avr_runner: avr8js installed from package-lock.json')
      : const DoctorCheck(CheckStatus.problem, 'tool/avr_runner: npm packages not installed or out of date',
          fix: 'unodar setup --dev'));
  return checks;
}

/// `node --version` without the `v`, or null.
String? nodeVersion() {
  try {
    final run = Process.runSync('node', ['--version']);
    return run.exitCode == 0 ? '${run.stdout}'.trim().replaceFirst('v', '') : null;
  } on ProcessException {
    return null;
  }
}

/// Whether `npm ci` has installed exactly the runner's lockfile: npm writes `node_modules/.package-lock.json`, and
/// avr8js must be the locked version.
bool avrRunnerInstalled(String checkout) {
  final runner = p.join(checkout, 'tool', 'avr_runner');
  try {
    final lock = jsonDecode(File(p.join(runner, 'package-lock.json')).readAsStringSync()) as Map<String, Object?>;
    final locked =
        ((lock['packages'] as Map<String, Object?>)['node_modules/avr8js'] as Map<String, Object?>)['version'];
    final installed = jsonDecode(File(p.join(runner, 'node_modules', 'avr8js', 'package.json')).readAsStringSync())
        as Map<String, Object?>;
    return File(p.join(runner, 'node_modules', '.package-lock.json')).existsSync() && installed['version'] == locked;
  } on Object {
    return false;
  }
}

/// The unodar checkout containing [directory] (or one of its parents), or null.
String? findCheckout(String directory) {
  var dir = p.absolute(directory);
  while (true) {
    if (File(p.join(dir, 'tool', 'avr_runner', 'package-lock.json')).existsSync() &&
        File(p.join(dir, 'packages', 'unodar_compiler', 'pubspec.yaml')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

bool _atLeast(String version, List<int> minimum) {
  final parts = version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (var i = 0; i < minimum.length; i++) {
    final part = i < parts.length ? parts[i] : 0;
    if (part != minimum[i]) return part > minimum[i];
  }
  return true;
}

/// The doctor's report: a header, one line per check (fixes indented under it), and a summary.
String renderDoctor(List<DoctorCheck> checks) {
  final problems = checks.where((c) => c.status == CheckStatus.problem).length;
  final fixes = {
    for (final c in checks)
      if (c.status == CheckStatus.problem && c.fix != null) c.fix!
  };
  final dart = Platform.version.split(' ').first;
  return [
    'unodar $unodarVersion (Dart $dart, ${platformName()})',
    for (final check in checks) ...[
      '  ${check.status.symbol} ${check.text}',
      if (check.fix != null && check.status != CheckStatus.ok && check.status != CheckStatus.info)
        '      fix: ${check.fix}',
    ],
    if (problems == 0)
      'Ready.'
    else
      '$problems ${problems == 1 ? 'problem' : 'problems'}. '
          '${fixes.length == 1 ? 'Run `${fixes.single}` to fix ${problems == 1 ? 'it' : 'them'}.' : 'Run the fixes above.'}',
  ].join('\n');
}

/// The platform as Dart names it, e.g. `macos_arm64` (the end of `Platform.version`).
String platformName() =>
    RegExp(r'on "([a-z0-9_]+)"').firstMatch(Platform.version)?.group(1) ?? Platform.operatingSystem;

String _tilde(String path) {
  final home = Platform.environment['HOME'];
  return home != null && home.isNotEmpty && p.isWithin(home, path) ? '~/${p.relative(path, from: home)}' : path;
}
