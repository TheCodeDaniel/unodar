/// Every first-party binding conforms to its C++ header (docs/DECISIONS.md, Phase 6 step 11): the conformance probe
/// calls each bound method and constructor with exactly the declared C++ parameter types and checks the declared
/// result types, and arduino-cli must compile it. The negative control declares a wrong result type, which the
/// probe must reject.
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/api/api_registry.dart';
import 'package:unodar_compiler/src/api/binding_reader.dart';
import 'package:unodar_compiler/src/api/conformance_probe.dart';
import 'package:unodar_compiler/src/emitter/target.dart';

import 'arduino_toolchain.dart';
import 'resolve_snippet.dart';
import 'test_paths.dart';

void main() {
  final gate = arduinoGate();
  final resolve = snippetResolver('.conformance_tmp');
  late ApiBindings bindings;

  setUpAll(() async {
    // Every public library of package:unodar: unodar.dart and each library wrapper (eeprom.dart, …).
    final imports = [
      for (final file in Directory(fromPackage('..', 'unodar', 'lib')).listSync().whereType<File>())
        if (file.path.endsWith('.dart')) "import 'package:unodar/${p.basename(file.path)}';",
    ]..sort();
    final library = await resolve('${imports.join('\n')}\n\nvoid setup() {}\n\nvoid loop() {}\n');
    bindings = const BindingReader(UnoTarget()).readImportedUnodar(library);
  });

  test('the first-party bindings (Wire, Servo, EEPROM) are probed, and the probe compiles', () async {
    gate.check();
    expect(bindings.classes.map((c) => c.dartName), containsAll(['TwoWire', 'Servo', 'EepromClass']));
    final probe = conformanceProbe(bindings);
    expect(probe, contains('Wire.requestFrom('));
    expect(probe, contains('unodar_probe_value<Servo &>().attach('));
    expect(probe, contains('EEPROM.update(unodar_probe_value<int>(), unodar_probe_value<uint8_t>())'));
    final build = await compileSketch('conformance', probe);
    printOnFailure(probe);
    printOnFailure(build.rawOutput);
    expect(build.success, isTrue);
  });

  test('negative control: a binding that declares the wrong C++ result type does not compile', () async {
    gate.check();
    final servo = bindings.classes.firstWhere((c) => c.dartName == 'Servo');
    final read = servo.methods.firstWhere((m) => m.dartName == 'read');
    expect(read.cppReturnType, 'int', reason: 'the Servo binding changed; update the negative control');
    final wrong = ApiClass(servo.dartName,
        cppName: servo.cppName,
        header: servo.header,
        constructor: servo.constructor,
        methods: [
          for (final m in servo.methods)
            m == read
                ? ApiFunction(m.dartName,
                    cppName: m.cppName, parameters: m.parameters, returnType: m.returnType, cppReturnType: 'uint8_t')
                : m,
        ]);
    final build = await compileSketch('conformance_wrong', conformanceProbe(ApiBindings(classes: [wrong])));
    expect(build.success, isFalse);
    expect(build.rawOutput, contains('Servo.read: the call does not have the declared C++ type uint8_t'));
  });
}
