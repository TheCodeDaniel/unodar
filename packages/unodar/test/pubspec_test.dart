import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Guards PRD §9.9 criterion 5: the user-facing API package must stay free of compiler and Flutter dependencies.
///
/// `packages/unodar` is what end users import. If it ever pulled in `analyzer`, every user project would carry the
/// compiler's dependency tree; if it pulled in Flutter, it would violate NG2 outright.
void main() {
  final pubspec = loadYaml(File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
  final dependencies = (pubspec['dependencies'] as YamlMap?)?.keys.cast<String>().toSet() ?? <String>{};

  test('has no runtime dependencies at all', () {
    expect(dependencies, isEmpty, reason: 'packages/unodar is declarations only and must stay dependency-free');
  });

  test('does not depend on analyzer or Flutter in any section', () {
    const forbidden = {'analyzer', 'flutter', 'flutter_test', 'sky_engine'};
    for (final section in ['dependencies', 'dev_dependencies', 'dependency_overrides']) {
      final names = (pubspec[section] as YamlMap?)?.keys.cast<String>() ?? const <String>[];
      expect(names.toSet().intersection(forbidden), isEmpty, reason: 'forbidden dependency in $section');
    }
    expect(pubspec['flutter'], isNull, reason: 'a `flutter:` section would make this a Flutter package');
  });
}

/// Absolute root of this package, so the test passes from any working directory.
final String packageRoot = p.dirname(p.fromUri(Isolate.resolvePackageUriSync(Uri.parse('package:unodar/'))!));
