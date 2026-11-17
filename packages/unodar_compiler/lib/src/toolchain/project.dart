import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../version.dart';

/// The `package:unodar` that the Dart files in [directory] resolve: the nearest `.dart_tool/package_config.json`
/// at or above it, and the version in that package's `pubspec.yaml`. Null when there is no package config, or it
/// has no `unodar` (the analyzer then reports the import, E007).
({String version, String project})? resolvedUnodar(String directory) {
  var dir = p.absolute(directory);
  while (true) {
    final config = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) return _unodarIn(config, dir);
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

({String version, String project})? _unodarIn(File config, String project) {
  try {
    final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    final entry = (json['packages'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((package) => package['name'] == 'unodar')
        .firstOrNull;
    if (entry == null) return null;
    // rootUri is relative to the package_config.json file itself.
    final root = config.uri.resolve(entry['rootUri']! as String);
    final pubspec = File(p.join(p.fromUri(root), 'pubspec.yaml')).readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);
    return version == null ? null : (version: version, project: project);
  } on Object {
    return null;
  }
}

/// Null when the project of [directory] uses this compiler's `package:unodar` version (or none can be found);
/// otherwise the message for exit 3 (D7: the compiler reads the API from `package:unodar` by element, so another
/// version could be misread).
String? unodarVersionProblem(String directory) {
  final resolved = resolvedUnodar(directory);
  if (resolved == null || resolved.version == unodarVersion) return null;
  return 'the project in ${resolved.project} uses package:unodar ${resolved.version}, but this compiler is unodar '
      '$unodarVersion, and the two must be the same version.\n'
      'Either change the `ref:` of unodar in its pubspec.yaml to v$unodarVersion and run `dart pub get`, or install '
      'the compiler of the project\'s version:\n'
      '  dart pub global activate --source git https://github.com/TheCodeDaniel/unodar '
      '--git-path packages/unodar_compiler --git-ref v${resolved.version}';
}
