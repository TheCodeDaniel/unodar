import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Absolute path of the unodar_compiler package root, so tests pass whether `dart test` runs from the package
/// directory or from the repository root.
final String packageRoot = p.dirname(
  p.fromUri(Isolate.resolvePackageUriSync(Uri.parse('package:unodar_compiler/'))!),
);

/// [parts] joined onto [packageRoot].
String fromPackage(String part1, [String? part2, String? part3, String? part4]) =>
    p.join(packageRoot, part1, part2, part3, part4);
