import 'dart:convert';

import '../emitter/emitter.dart';
import 'toolchain.dart';

/// The outcome of `arduino-cli compile` on a sketch folder.
final class ArduinoCompileResult {
  const ArduinoCompileResult(
      {required this.success, this.flash, this.flashMax, this.ram, this.ramMax, this.errors = ''});

  final bool success;

  /// Bytes of program storage (the ELF `text` section) and its maximum on the board.
  final int? flash;
  final int? flashMax;

  /// Bytes of RAM taken by globals (the `data` section, as arduino-cli reports it) and the board's RAM.
  final int? ram;
  final int? ramMax;

  /// The compiler's error output when [success] is false.
  final String errors;

  /// `flash 924 B of 32256 (2 %), RAM 9 B of 2048 (0 %)`, rounded down like arduino-cli's own summary.
  String get sizeLine {
    String part(String name, int? used, int? max) =>
        used == null ? '' : '$name $used B${max == null || max == 0 ? '' : ' of $max (${used * 100 ~/ max} %)'}';
    return [part('flash', flash, flashMax), part('RAM', ram, ramMax)].where((s) => s.isNotEmpty).join(', ');
  }
}

/// Compiles the sketch in [sketchFolder] for [target] with its build properties (`-fwrapv`), caching the build in
/// [buildPath] (so `flash` can upload it and a rebuild is incremental).
Future<ArduinoCompileResult> compileSketchFolder(ArduinoCli cli,
    {required String sketchFolder, required String buildPath, Target target = const UnoTarget()}) async {
  final run = await cli.run([
    'compile',
    '--fqbn',
    target.fqbn,
    for (final property in target.buildProperties) ...['--build-property', property],
    '--build-path',
    buildPath,
    '--format',
    'json',
    sketchFolder,
  ]);
  Map<String, Object?>? json;
  try {
    json = jsonDecode('${run.stdout}') as Map<String, Object?>;
  } on FormatException {
    json = null;
  }
  final success = run.exitCode == 0 && json?['success'] == true;
  if (!success) {
    final errors = [json?['compiler_err'], json?['error'], if (json == null) run.stdout, run.stderr]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('\n');
    return ArduinoCompileResult(success: false, errors: errors);
  }
  final sections = ((json?['builder_result'] as Map<String, Object?>?)?['executable_sections_size'] as List<Object?>?)
          ?.cast<Map<String, Object?>>() ??
      const [];
  Map<String, Object?>? section(String name) => sections.where((s) => s['name'] == name).firstOrNull;
  return ArduinoCompileResult(
    success: true,
    flash: section('text')?['size'] as int?,
    flashMax: section('text')?['max_size'] as int?,
    ram: section('data')?['size'] as int?,
    ramMax: section('data')?['max_size'] as int?,
  );
}
