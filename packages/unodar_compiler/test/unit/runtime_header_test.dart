import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/runtime/runtime_files.dart';

import '../test_paths.dart';

/// The compiler writes its embedded copies of the runtime headers next to the programs that need them, while the
/// headers' own tests (runtime_fidelity_test.dart) run the files in `runtime/`. They must be the same text, and every
/// header in `runtime/` must be embedded.
void main() {
  final headers = [
    for (final file in Directory(fromPackage('..', '..', 'runtime')).listSync().whereType<File>())
      if (file.path.endsWith('.h')) file
  ];

  test('every header in runtime/ is embedded, and nothing else', () {
    expect(runtimeFiles.keys.toSet(), headers.map((f) => p.basename(f.path)).toSet(),
        reason: 'run tool/embed_runtime.sh and list the new header in runtime_files.dart');
  });

  for (final file in headers) {
    final name = p.basename(file.path);
    test('the embedded $name is identical to runtime/$name', () {
      expect(runtimeFiles[name], file.readAsStringSync(), reason: 'run tool/embed_runtime.sh to refresh the copy');
    });
  }
}
