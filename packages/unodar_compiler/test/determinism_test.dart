import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';

/// PRD §9.3: same input → byte-identical output.
void main() {
  final blink = p.join('test', 'golden', 'blink', 'input.dart');

  Future<String> compile(String path) async => switch (await Compiler().compile(path)) {
        CompileSuccess(:final cpp) => cpp,
        final other => fail('expected success, got $other'),
      };

  test('compiling the same file twice gives identical output', () async {
    expect(await compile(blink), await compile(blink));
  });

  test('output does not depend on where the file lives on disk', () async {
    // A copy inside the same package (so package:unodar still resolves) but at a different absolute path.
    final dir = Directory(p.join('test', '.determinism_tmp', 'nested'))..createSync(recursive: true);
    addTearDown(() => dir.parent.deleteSync(recursive: true));
    final copy = File(blink).copySync(p.join(dir.path, 'input.dart'));
    expect(await compile(copy.path), await compile(blink));
  });

  test('output contains no absolute paths', () async {
    expect(await compile(blink), isNot(contains(Directory.current.path)));
  });
}
