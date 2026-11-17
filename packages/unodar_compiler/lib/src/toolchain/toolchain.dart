import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'pins.dart';

/// Where `unodar setup` keeps the managed toolchain: `$UNODAR_HOME`, else `~/.unodar` (PRD §8.1). Nothing outside
/// it is ever written: arduino-cli gets its own data, sketchbook and download directories through [configFile].
final class UnodarHome {
  const UnodarHome(this.path);

  /// `UNODAR_HOME` from [environment], else `.unodar` in the home directory.
  factory UnodarHome.fromEnvironment(Map<String, String> environment) {
    final explicit = environment['UNODAR_HOME'];
    if (explicit != null && explicit.isNotEmpty) return UnodarHome(p.absolute(explicit));
    final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '.';
    return UnodarHome(p.join(home, '.unodar'));
  }

  final String path;

  String get cli => p.join(path, 'bin', Platform.isWindows ? 'arduino-cli.exe' : 'arduino-cli');
  String get configFile => p.join(path, 'arduino-cli.yaml');
  String get dataDirectory => p.join(path, 'data');
  String get userDirectory => p.join(path, 'user');
  String get downloadsDirectory => p.join(path, 'downloads');

  /// The arduino-cli configuration that keeps everything inside [path].
  String get configYaml => '''
# Written by `unodar setup`. Keeps arduino-cli's cores, libraries and downloads inside this folder.
directories:
  data: $dataDirectory
  user: $userDirectory
  downloads: $downloadsDirectory
''';
}

/// One arduino-cli executable, with the configuration file it must be run with (the managed one), or none (one on
/// `PATH`, which uses its own configuration).
final class ArduinoCli {
  const ArduinoCli(this.executable, {this.configFile, required this.managed});

  final String executable;
  final String? configFile;

  /// Whether this is the copy in `~/.unodar`.
  final bool managed;

  /// [arguments], plus `--config-file` for the managed copy.
  List<String> arguments(List<String> arguments) => [
        ...arguments,
        if (configFile != null) ...['--config-file', configFile!]
      ];

  ProcessResult runSync(List<String> args) => Process.runSync(executable, arguments(args));

  Future<ProcessResult> run(List<String> args) => Process.run(executable, arguments(args));

  @override
  String toString() => executable;
}

/// What an arduino-cli reports as installed.
final class ToolchainInventory {
  const ToolchainInventory({required this.cliVersion, required this.cores, required this.libraries});

  final String cliVersion;

  /// Installed version by core id (`arduino:avr` → `1.8.8`).
  final Map<String, String> cores;

  /// Installed version by library name.
  final Map<String, String> libraries;

  /// Runs `version`, `core list` and `lib list` (JSON). Throws a [ToolchainException] when one fails or prints
  /// something unreadable.
  static ToolchainInventory read(ArduinoCli cli) {
    Map<String, Object?> json(List<String> args) {
      final ProcessResult run;
      try {
        run = cli.runSync([...args, '--format', 'json']);
      } on ProcessException catch (e) {
        throw ToolchainException('$cli cannot be run: ${e.message}');
      }
      if (run.exitCode != 0) {
        throw ToolchainException('`arduino-cli ${args.join(' ')}` failed: ${'${run.stderr}'.trim()}');
      }
      try {
        return jsonDecode(run.stdout as String) as Map<String, Object?>;
      } on FormatException {
        throw ToolchainException('`arduino-cli ${args.join(' ')}` printed something unreadable');
      }
    }

    final version = json(['version'])['VersionString'];
    final platforms = (json(['core', 'list'])['platforms'] as List<Object?>? ?? const []).cast<Map<String, Object?>>();
    final libraries =
        (json(['lib', 'list'])['installed_libraries'] as List<Object?>? ?? const []).cast<Map<String, Object?>>();
    return ToolchainInventory(
      cliVersion: version is String ? version : '?',
      cores: {
        for (final platform in platforms)
          if ((platform['id'], platform['installed_version']) case (final String id, final String version)) id: version,
      },
      libraries: {
        for (final entry in libraries)
          if (entry['library'] case {'name': final String name, 'version': final String version}) name: version,
      },
    );
  }

  /// What differs from [pins], one sentence each; empty when this inventory has the pinned core and libraries (and,
  /// with [requireCliVersion], the pinned arduino-cli).
  List<String> problems(ToolchainPins pins, {required bool requireCliVersion}) => [
        if (requireCliVersion && cliVersion != pins.cliVersion)
          'arduino-cli is $cliVersion, but unodar is tested with ${pins.cliVersion}',
        switch (cores[pins.core.name]) {
          null => 'the ${pins.core.name} core is not installed',
          final v when v != pins.core.version =>
            'the ${pins.core.name} core is $v, but unodar is tested with ${pins.core.version}',
          _ => null,
        },
        for (final library in pins.libraries)
          switch (libraries[library.name]) {
            null => 'the library ${library.name} is not installed',
            final v when v != library.version =>
              'the library ${library.name} is $v, but unodar is tested with ${library.version}',
            _ => null,
          },
      ].nonNulls.toList();
}

/// arduino-cli could not be run or read.
final class ToolchainException implements Exception {
  const ToolchainException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The result of looking for a usable toolchain.
sealed class ToolchainLookup {
  const ToolchainLookup();
}

/// A usable toolchain: the managed copy, or else an `arduino-cli` on `PATH` with the pinned core and libraries.
final class ToolchainFound extends ToolchainLookup {
  const ToolchainFound(this.cli, this.inventory);

  final ArduinoCli cli;
  final ToolchainInventory inventory;
}

/// No usable toolchain; [reasons] says what is wrong with each candidate, for the error message.
final class ToolchainNotFound extends ToolchainLookup {
  const ToolchainNotFound(this.reasons);

  final List<String> reasons;

  /// The message commands print before exiting with code 3.
  String get message => [
        'no usable Arduino toolchain:',
        for (final reason in reasons) '  - $reason',
        'Run `unodar setup` to install the tested toolchain into ~/.unodar (nothing else on your system changes).',
      ].join('\n');
}

/// The managed arduino-cli in [home], if it is there (its version is not checked here).
ArduinoCli? managedCli(UnodarHome home) =>
    File(home.cli).existsSync() ? ArduinoCli(home.cli, configFile: home.configFile, managed: true) : null;

/// The first `arduino-cli` on [environment]'s `PATH`, or null.
ArduinoCli? pathCli(Map<String, String> environment) {
  final names = Platform.isWindows ? ['arduino-cli.exe'] : ['arduino-cli'];
  for (final dir in (environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final name in names) {
      final candidate = p.join(dir, name);
      if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
        return ArduinoCli(candidate, managed: false);
      }
    }
  }
  return null;
}

/// Finds the toolchain every command and the `arduino` tests use (DECISIONS 2026-11-17, Phase 7): the managed copy
/// in [home] first, with the pinned arduino-cli, core and libraries; otherwise an `arduino-cli` on `PATH`, accepted
/// only with the pinned core and libraries (its own version is not required).
ToolchainLookup locateToolchain(
    {required UnodarHome home, required Map<String, String> environment, ToolchainPins? pins}) {
  pins ??= ToolchainPins.embedded;
  final reasons = <String>[];
  for (final cli in [managedCli(home), pathCli(environment)].nonNulls) {
    final where = cli.managed ? 'the managed arduino-cli (${home.path})' : 'arduino-cli on PATH (${cli.executable})';
    try {
      final inventory = ToolchainInventory.read(cli);
      final problems = inventory.problems(pins, requireCliVersion: cli.managed);
      if (problems.isEmpty) return ToolchainFound(cli, inventory);
      reasons.add('$where: ${problems.join('; ')}');
    } on ToolchainException catch (e) {
      reasons.add('$where: ${e.message}');
    }
  }
  if (managedCli(home) == null) reasons.insert(0, 'no managed toolchain in ${home.path}');
  if (pathCli(environment) == null) reasons.add('no arduino-cli on PATH');
  return ToolchainNotFound(reasons);
}
