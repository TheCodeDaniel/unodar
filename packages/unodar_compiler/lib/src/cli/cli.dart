import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../compiler.dart';
import '../toolchain/arduino_build.dart';
import '../toolchain/doctor.dart';
import '../toolchain/setup.dart';
import '../toolchain/toolchain.dart';
import '../version.dart';

/// Process exit codes (PRD §9.6; 3 and 4 from Phase 7, see docs/DIAGNOSTICS.md "Exit codes").
abstract final class ExitCodes {
  /// The command succeeded (`doctor`: everything is ready).
  static const success = 0;

  /// The user's Dart source has diagnostics.
  static const diagnostics = 1;

  /// Anything that is not a problem in the user's source: bad usage, unreadable input, I/O failure, compiler bug.
  static const tooling = 2;

  /// The Arduino toolchain is missing, has the wrong version, or cannot run (`doctor` found a problem; a download
  /// failed). The fix is `unodar setup`.
  static const toolchain = 3;

  /// The board: none found, several found without `--port`, the port busy or not permitted, or the upload failed.
  static const board = 4;
}

/// What a command runs with: its output streams, the environment and the working directory (injectable so that
/// tests run commands in-process against fake toolchains).
final class CliContext {
  const CliContext({required this.out, required this.err, required this.environment, required this.workingDirectory});

  final StringSink out;
  final StringSink err;
  final Map<String, String> environment;
  final String workingDirectory;

  UnodarHome get home => UnodarHome.fromEnvironment(environment);

  /// [path] relative to [workingDirectory].
  String resolve(String path) => p.normalize(p.join(workingDirectory, path));
}

/// One subcommand.
final class _Command {
  const _Command(this.name, this.summary, this.usage, this.parser, this.run);

  final String name;
  final String summary;
  final String usage;
  final ArgParser Function() parser;
  final Future<int> Function(ArgResults args, CliContext context) run;
}

ArgParser _withHelp(ArgParser parser) => parser..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

final _commands = [
  _Command(
    'build',
    'Compile a Dart program to C++ (<outdir>/<name>/<name>.ino) and build it for the Uno',
    'unodar build [<file.dart>] [-o <outdir>] [--cpp-only]',
    () => _withHelp(ArgParser()
      ..addOption('output',
          abbr: 'o', valueHelp: 'outdir', defaultsTo: 'build', help: 'Directory to write the sketch into.')
      ..addFlag('cpp-only',
          negatable: false, help: 'Only write the C++; do not build it with arduino-cli (needs no toolchain).')),
    _build,
  ),
  _Command(
    'doctor',
    'Check the Arduino toolchain and say how to fix what is missing',
    'unodar doctor [--dev]',
    () => _withHelp(ArgParser()
      ..addFlag('dev',
          negatable: false, help: 'Also check what contributors need: Node.js and the avr8js runner of the tests.')),
    _doctor,
  ),
  _Command(
    'setup',
    'Install the tested Arduino toolchain into ~/.unodar (safe to re-run)',
    'unodar setup [--dev]',
    () => _withHelp(ArgParser()
      ..addFlag('dev',
          negatable: false,
          help: 'Also install what the tests of a unodar checkout need (npm ci in tool/avr_runner; Node.js itself is '
              'yours to install).')),
    _setup,
  ),
];

String get _usageHeader => '''
unodar: compile Flutter-style Dart to Arduino C++ (experimental).

Usage: unodar <command> [arguments]

Commands:
${_commands.map((c) => '  ${c.name.padRight(8)} ${c.summary}').join('\n')}

Options:
  -h, --help       Show this help.
      --version    Print the version of unodar.

Run "unodar <command> --help" for command options.''';

ArgParser _globalParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
  ..addFlag('version', negatable: false, help: 'Print the version of unodar.');

/// Entry point for the `unodar` CLI. Returns the process exit code; writes only to [out] and [err] so tests can run
/// it in-process. `bin/unodar.dart` wires these to stdout/stderr. [environment] and [workingDirectory] default to
/// the process's own.
Future<int> runCli(List<String> arguments,
    {required StringSink out,
    required StringSink err,
    Map<String, String>? environment,
    String? workingDirectory}) async {
  final context = CliContext(
      out: out,
      err: err,
      environment: environment ?? Platform.environment,
      workingDirectory: workingDirectory ?? Directory.current.path);
  try {
    final global = _globalParser();
    final ArgResults top;
    try {
      // Global flags come before the command name; everything after it belongs to the command.
      final commandIndex = arguments.indexWhere((a) => !a.startsWith('-'));
      top = global.parse(commandIndex == -1 ? arguments : arguments.sublist(0, commandIndex));
      if (top.flag('help')) {
        out.writeln(_usageHeader);
        return ExitCodes.success;
      }
      if (top.flag('version')) {
        out.writeln('unodar $unodarVersion');
        return ExitCodes.success;
      }
      if (commandIndex == -1) return _usageError(err, 'missing command.');
      final name = arguments[commandIndex];
      final command = _commands.where((c) => c.name == name).firstOrNull;
      if (command == null) return _usageError(err, 'unknown command "$name".');
      final parser = command.parser();
      final ArgResults args;
      try {
        args = parser.parse(arguments.sublist(commandIndex + 1));
      } on FormatException catch (e) {
        return _commandUsageError(err, command, parser, e.message);
      }
      if (args.flag('help')) {
        out
          ..writeln('${command.summary}.')
          ..writeln()
          ..writeln('Usage: ${command.usage}')
          ..writeln()
          ..writeln(parser.usage);
        return ExitCodes.success;
      }
      return await command.run(args, context);
    } on _UsageException catch (e) {
      final command = _commands.firstWhere((c) => c.name == e.command);
      return _commandUsageError(err, command, command.parser(), e.message);
    } on FormatException catch (e) {
      return _usageError(err, e.message);
    }
  } catch (e, stack) {
    // A crash here is a compiler bug, never the user's fault: say so and exit with the tooling code.
    err
      ..writeln('internal error: $e')
      ..writeln('This is a bug in unodar. Please report it at $issuesUrl with the input file and this trace:')
      ..writeln(stack);
    return ExitCodes.tooling;
  }
}

/// Where bugs are reported.
const issuesUrl = 'https://github.com/TheCodeDaniel/unodar/issues';

final class _UsageException implements Exception {
  const _UsageException(this.command, this.message);

  final String command;
  final String message;
}

int _usageError(StringSink err, String message) {
  err
    ..writeln('error: $message')
    ..writeln()
    ..writeln(_usageHeader);
  return ExitCodes.tooling;
}

int _commandUsageError(StringSink err, _Command command, ArgParser parser, String message) {
  err
    ..writeln('error: $message')
    ..writeln()
    ..writeln('Usage: ${command.usage}')
    ..writeln(parser.usage);
  return ExitCodes.tooling;
}

Future<int> _build(ArgResults args, CliContext context) async =>
    (await buildProgram(args, context, cppOnly: args.flag('cpp-only'))).exitCode;

/// What [buildProgram] produced: the exit code, and on success the sketch folder and arduino-cli's build folder.
typedef BuiltProgram = ({int exitCode, String? sketchFolder, String? buildPath, ArduinoCli? cli});

/// `unodar build`, also the first half of `flash`: Dart to C++ (diagnostics are exit 1), the sketch written to
/// `<outdir>/<name>/`, then, unless [cppOnly], `arduino-cli compile` with `-fwrapv` into `<outdir>/.build/<name>`
/// and the size line. The input defaults to `main.dart` in the working directory.
Future<BuiltProgram> buildProgram(ArgResults args, CliContext context,
    {required bool cppOnly, String command = 'build'}) async {
  if (args.rest.length > 1) throw _UsageException(command, 'expected at most one <file.dart>.');
  final input = args.rest.isEmpty ? 'main.dart' : args.rest.single;
  final err = context.err;
  final CompileSuccess result;
  switch (await Compiler().compile(context.resolve(input))) {
    case final CompileSuccess success:
      result = success;
    case CompileFailure(:final diagnostics):
      for (final diagnostic in diagnostics) {
        err.writeln(diagnostic.format());
      }
      err.writeln('${diagnostics.length} ${diagnostics.length == 1 ? 'error' : 'errors'}.');
      return (exitCode: ExitCodes.diagnostics, sketchFolder: null, buildPath: null, cli: null);
    case CompileInputError(:final message):
      err.writeln('error: $message');
      return (exitCode: ExitCodes.tooling, sketchFolder: null, buildPath: null, cli: null);
  }
  final output = args.option('output')!;
  final name = p.basenameWithoutExtension(input);
  final String ino;
  try {
    ino = writeSketch(context.resolve(output), name, result);
  } on FileSystemException catch (e) {
    err.writeln('error: could not write ${e.path ?? output}: ${e.osError?.message ?? e.message}');
    return (exitCode: ExitCodes.tooling, sketchFolder: null, buildPath: null, cli: null);
  }
  // Printed as given: relative to the working directory when `-o` was relative.
  context.out.writeln(p.isAbsolute(output) ? ino : p.relative(ino, from: context.workingDirectory));
  if (cppOnly) return (exitCode: ExitCodes.success, sketchFolder: p.dirname(ino), buildPath: null, cli: null);

  final ArduinoCli cli;
  switch (locateToolchain(home: context.home, environment: context.environment)) {
    case ToolchainFound(cli: final found):
      cli = found;
    case final ToolchainNotFound missing:
      err
        ..writeln('error: ${missing.message}')
        ..writeln('(`unodar build --cpp-only` writes only the C++, which needs no toolchain.)');
      return (exitCode: ExitCodes.toolchain, sketchFolder: p.dirname(ino), buildPath: null, cli: null);
  }
  final buildPath = p.join(context.resolve(output), '.build', name);
  final compiled = await compileSketchFolder(cli, sketchFolder: p.dirname(ino), buildPath: buildPath);
  if (!compiled.success) {
    err
      ..writeln(compiled.errors)
      ..writeln();
    if (result.bringsOwnCpp) {
      err.writeln('error: the C++ did not compile. This program contains C++ of its own (`cpp(…)`, `@CppInclude` or a '
          'binding class), so check that first; the locations above point into your Dart file.');
      return (exitCode: ExitCodes.diagnostics, sketchFolder: p.dirname(ino), buildPath: null, cli: cli);
    }
    err.writeln('error: the C++ that unodar generated does not compile. This is a bug in unodar. Please report it at '
        '$issuesUrl with your Dart file and the sketch folder ${p.dirname(ino)}.');
    return (exitCode: ExitCodes.tooling, sketchFolder: p.dirname(ino), buildPath: null, cli: cli);
  }
  context.out.writeln(compiled.sizeLine);
  return (exitCode: ExitCodes.success, sketchFolder: p.dirname(ino), buildPath: buildPath, cli: cli);
}

Future<int> _doctor(ArgResults args, CliContext context) async {
  final dev = args.flag('dev');
  final checks = runDoctor(
      home: context.home,
      environment: context.environment,
      dev: dev,
      checkout: dev ? findCheckout(context.workingDirectory) : null);
  context.out.writeln(renderDoctor(checks));
  return checks.any((c) => c.status == CheckStatus.problem) ? ExitCodes.toolchain : ExitCodes.success;
}

Future<int> _setup(ArgResults args, CliContext context) {
  final dev = args.flag('dev');
  return runSetup(
      home: context.home,
      environment: context.environment,
      out: context.out,
      err: context.err,
      dev: dev,
      checkout: dev ? findCheckout(context.workingDirectory) : null);
}

/// Writes [result] as `<outDir>/<name>/<name>.ino` (arduino-cli requires the sketch folder and the `.ino` to share a
/// name), plus its extra files (the widget runtime header) in the same folder, and returns the `.ino` path. A file
/// from an earlier build that this program no longer needs is left alone: arduino-cli only compiles a header that
/// something includes.
String writeSketch(String outDir, String name, CompileSuccess result) {
  final folder = Directory(p.join(outDir, name))..createSync(recursive: true);
  final ino = File(p.join(folder.path, '$name.ino'))..writeAsStringSync(result.cpp, flush: true);
  for (final MapEntry(key: fileName, value: contents) in result.files.entries) {
    File(p.join(folder.path, fileName)).writeAsStringSync(contents, flush: true);
  }
  return ino.path;
}
