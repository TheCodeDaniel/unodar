import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/runtime/unodar_widgets_header.dart';

import '../test_paths.dart';

/// The compiler writes its embedded copy of the widget runtime next to every widget program, while the runtime's
/// own tests (runtime_fidelity_test.dart) run `runtime/unodar_widgets.h`. They must be the same text.
void main() {
  test('the embedded widget runtime is identical to runtime/unodar_widgets.h', () {
    final header = File(fromPackage('..', '..', 'runtime', 'unodar_widgets.h')).readAsStringSync();
    expect(unodarWidgetsHeader, header, reason: 'run tool/embed_runtime.sh to refresh the embedded copy');
  });
}
