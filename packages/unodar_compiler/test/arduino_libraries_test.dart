/// `tool/arduino_libraries.txt` lists every dependency of every library in it, read from the installed libraries'
/// own `library.properties` (maintainer requirement: CI installs with `--no-deps`, so an unlisted dependency would
/// only surface as a compile error later). The checker itself, with a negative control, is in
/// `unit/toolchain_gate_test.dart`.
@Tags(['arduino'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'arduino_toolchain.dart';

void main() {
  final gate = arduinoGate();

  test('every depends= of an installed manifest library is in the manifest', () {
    gate.check();
    final list = testCli!.runSync(['lib', 'list', '--format', 'json']);
    expect(list.exitCode, 0, reason: '${list.stderr}');
    final installed = {
      for (final entry in (jsonDecode(list.stdout as String)['installed_libraries'] as List? ?? const []))
        (entry['library']['name'] as String): entry['library']['install_dir'] as String,
    };
    final depends = <String, List<String>>{};
    for (final library in arduinoLibraries) {
      final dir = installed[library.name];
      expect(dir, isNotNull, reason: '${library.name} is not installed: ${installCommand(library)}');
      depends[library.name] = dependsOf(File(p.join(dir!, 'library.properties')).readAsStringSync());
    }
    expect(undeclaredDependencies(arduinoLibraries, depends), isEmpty);
  });
}
