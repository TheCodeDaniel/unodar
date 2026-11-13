import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../compiler.dart';

/// Process exit codes (PRD §9.6).
abstract final class ExitCodes {
  /// The sketch compiled.
  static const success = 0;

  /// The user's Dart source has diagnostics.
  static const diagnostics = 1;

  /// Anything that is not a problem in the user's source: bad usage, unreadable input, I/O failure, compiler bug.
  static const tooling = 2;
}

const _usageHeader = '''
unodar: compile Flutter-style Dart to Arduino C++ (experimental).

Usage: unodar <command> [arguments]

Commands:
  build    Compile a Dart sketch to <outdir>/<name>/<name>.ino

Run "unodar build --help" for command options.''';

ArgParser _globalParser() => ArgParser()..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

ArgParser _buildParser() => ArgParser()
  ..addOption('output',
      abbr: 'o', valueHelp: 'outdir', defaultsTo: 'build', help: 'Directory to write the sketch into.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

/// Entry point for the `unodar` CLI. Returns the process exit code; writes only to [out] and [err] so tests can run
/// it in-process. `bin/unodar.dart` wires these to stdout/stderr.
Future<int> runCli(List<String> arguments, {required StringSink out, required StringSink err}) async {
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
      if (commandIndex == -1) return _usageError(err, 'missing command.');
      final command = arguments[commandIndex];
      final rest = arguments.sublist(commandIndex + 1);
      return switch (command) {
        'build' => await _build(rest, out: out, err: err),
        _ => _usageError(err, 'unknown command "$command".'),
      };
    } on FormatException catch (e) {
      return _usageError(err, e.message);
    }
  } catch (e, stack) {
    // A crash here is a compiler bug, never the user's fault: say so and exit with the tooling code.
    err
      ..writeln('internal error: $e')
      ..writeln('This is a bug in unodar. Please report it with the input file and this trace:')
      ..writeln(stack);
    return ExitCodes.tooling;
  }
}

int _usageError(StringSink err, String message) {
  err
    ..writeln('error: $message')
    ..writeln()
    ..writeln(_usageHeader);
  return ExitCodes.tooling;
}

Future<int> _build(List<String> arguments, {required StringSink out, required StringSink err}) async {
  final parser = _buildParser();
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    return _buildUsageError(err, parser, e.message);
  }
  if (args.flag('help')) {
    out
      ..writeln('Compile a Dart sketch to Arduino C++.')
      ..writeln()
      ..writeln('Usage: unodar build <file.dart> [-o <outdir>]')
      ..writeln()
      ..writeln(parser.usage);
    return ExitCodes.success;
  }
  if (args.rest.length != 1) return _buildUsageError(err, parser, 'expected exactly one <file.dart>.');

  final input = args.rest.single;
  switch (await Compiler().compile(input)) {
    case final CompileSuccess result:
      final String ino;
      try {
        ino = writeSketch(args.option('output')!, p.basenameWithoutExtension(input), result);
      } on FileSystemException catch (e) {
        err.writeln('error: could not write ${e.path ?? args.option('output')}: ${e.osError?.message ?? e.message}');
        return ExitCodes.tooling;
      }
      out.writeln(ino);
      return ExitCodes.success;
    case CompileFailure(:final diagnostics):
      for (final diagnostic in diagnostics) {
        err.writeln(diagnostic.format());
      }
      err.writeln('${diagnostics.length} ${diagnostics.length == 1 ? 'error' : 'errors'}.');
      return ExitCodes.diagnostics;
    case CompileInputError(:final message):
      err.writeln('error: $message');
      return ExitCodes.tooling;
  }
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

int _buildUsageError(StringSink err, ArgParser parser, String message) {
  err
    ..writeln('error: $message')
    ..writeln()
    ..writeln('Usage: unodar build <file.dart> [-o <outdir>]')
    ..writeln(parser.usage);
  return ExitCodes.tooling;
}
