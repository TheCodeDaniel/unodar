import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';

import '../test_paths.dart';

/// Phase 5 declares `Signal`, `Watch`, `Led(on:)` and `Led.set` in `package:unodar` (plan step 3) before the
/// compiler supports them (steps 5–9). Until then every use must be rejected with diagnostics (exit 1), never
/// compile and never stop with an internal error (exit 2): "reject loudly, never miscompile".
///
/// Each later step deletes the snippet of the construct it implements and adds that construct's goldens; the file
/// is deleted when the list is empty.
void main() {
  final scratch = Directory(fromPackage('test', '.pending_tmp'));
  setUpAll(() => scratch.createSync(recursive: true));
  tearDownAll(() => scratch.deleteSync(recursive: true));

  const header = "import 'package:unodar/unodar.dart';\n\n";
  const pending = <String, String>{
    // Plan step 8 (also golden e003_widget_method).
    'Led.set': 'final led = Led(pin: 13);\n\n'
        'void main() => runDevice(Device(board: Uno(), children: [led, '
        'Every(Duration(seconds: 1), () { led.set(true); })]));\n',
    // Plan step 9.
    'Led(on:)': 'final lit = Signal(true);\nfinal led = Led(pin: 13, on: lit);\n\n'
        'void main() => runDevice(Device(board: Uno(), children: [led]));\n',
  };

  for (final MapEntry(key: name, value: body) in pending.entries) {
    test('$name is rejected with diagnostics until its compiler step', () async {
      final dir = Directory(p.join(scratch.path, name.replaceAll(RegExp('[^a-z]+', caseSensitive: false), '_')))
        ..createSync(recursive: true);
      final file = File(p.join(dir.path, 'input.dart'))..writeAsStringSync(header + body);
      // An internal error surfaces as a thrown LoweringError (exit 2 in the CLI), which fails this test too.
      final result = await Compiler().compile(file.path);
      expect(result, isA<CompileFailure>(), reason: '$result');
    });
  }
}
