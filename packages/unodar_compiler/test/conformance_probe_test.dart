/// Every first-party binding conforms to its C++ header (docs/DECISIONS.md, Phase 6 step 11): the conformance probe
/// calls each bound method and constructor with exactly the declared C++ parameter types and checks the declared
/// result types, and arduino-cli must compile it. The negative control declares a wrong result type, which the
/// probe must reject.
@Tags(['arduino'])
library;

import 'package:test/test.dart';
import 'package:unodar_compiler/src/api/api_registry.dart';
import 'package:unodar_compiler/src/api/binding_reader.dart';
import 'package:unodar_compiler/src/api/conformance_probe.dart';
import 'package:unodar_compiler/src/emitter/target.dart';

import 'arduino_toolchain.dart';
import 'resolve_snippet.dart';

void main() {
  final gate = arduinoGate();
  final resolve = snippetResolver('.conformance_tmp');
  late ApiBindings bindings;

  setUpAll(() async {
    final library = await resolve("import 'package:unodar/unodar.dart';\n\nvoid setup() {}\n\nvoid loop() {}\n");
    bindings = const BindingReader(UnoTarget()).readImportedUnodar(library);
  });

  test('the first-party bindings (Wire, Servo) are probed, and the probe compiles', () async {
    gate.check();
    expect(bindings.classes.map((c) => c.dartName), containsAll(['TwoWire', 'Servo']));
    final probe = conformanceProbe(bindings);
    expect(probe, contains('Wire.requestFrom('));
    expect(probe, contains('unodar_probe_value<Servo &>().attach('));
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
