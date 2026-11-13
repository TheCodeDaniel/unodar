import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/frontend/frontend.dart';

import 'test_paths.dart';

/// Resolves Dart snippets inside this package, so that `package:unodar` resolves, and returns their libraries.
/// Call once per test file, at the top of `main`; the scratch directory [name] is removed after the tests.
Future<LibraryElement> Function(String dart) snippetResolver(String name) {
  final scratch = Directory(fromPackage('test', name));
  setUpAll(() => scratch.createSync(recursive: true));
  tearDownAll(() => scratch.deleteSync(recursive: true));
  var count = 0;
  return (dart) async {
    final dir = Directory(p.join(scratch.path, '${count++}'))..createSync();
    final file = File(p.join(dir.path, 'input.dart'))..writeAsStringSync(dart);
    final result = await const Frontend().resolve(file.path);
    if (result is! FrontendSuccess) fail('could not resolve the snippet: $result');
    if (result.analysisErrors.isNotEmpty) {
      fail('the snippet has analyzer errors: ${result.analysisErrors.map((e) => e.diagnostic.format()).join('\n')}');
    }
    return result.source.unit.declaredFragment!.element;
  };
}
