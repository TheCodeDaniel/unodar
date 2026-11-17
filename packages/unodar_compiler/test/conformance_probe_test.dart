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
import 'package:unodar_compiler/src/runtime/runtime_files.dart';

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

  test('the first-party bindings (Wire, Servo, EEPROM, SPI, SoftwareSerial, LiquidCrystal) are probed and compile',
      () async {
    gate.check();
    expect(bindings.classes.map((c) => c.dartName),
        containsAll(['TwoWire', 'Servo', 'EepromClass', 'SpiClass', 'SoftwareSerial', 'LiquidCrystal']));
    final probe = conformanceProbe(bindings);
    expect(probe, contains('Wire.requestFrom('));
    expect(probe, contains('unodar_probe_value<Servo &>().attach('));
    expect(probe, contains('EEPROM.update(unodar_probe_value<int>(), unodar_probe_value<uint8_t>())'));
    // A shim header comes from the sketch folder; a named constant must have the C++ value.
    expect(probe, contains('#include "unodar_spi.h"'));
    expect(probe, contains('unodar_spi.beginTransaction(unodar_probe_value<uint32_t>(), '));
    expect(probe, contains('static_assert(MSBFIRST == 1,'));
    expect(probe, contains('SoftwareSerial(unodar_probe_value<uint8_t>(), unodar_probe_value<uint8_t>(), '));
    expect(probe, contains('unodar_probe_print(static_cast<SoftwareSerial *>(nullptr))'));
    expect(probe, contains('unodar_probe_print(static_cast<LiquidCrystal *>(nullptr))'));
    expect(probe, contains('unodar_probe_value<LiquidCrystal &>().setCursor('));
    expect(probe, isNot(contains('SPI_MODE1 ==')), reason: 'a constant without @CppName is emitted as its value');
    final build = await compileSketch('conformance', probe, files: runtimeFiles);
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

  test('negative control: a wrapper constant whose value differs from its C++ macro does not compile', () async {
    gate.check();
    final wrong = [
      for (final c in bindings.constants)
        c.dartName == 'MSBFIRST' ? ApiConstant(c.dartName, cppName: c.cppName, value: 0) : c,
    ];
    expect(bindings.constants.map((c) => c.dartName), contains('MSBFIRST'));
    final build = await compileSketch('conformance_constant',
        conformanceProbe(ApiBindings(classes: bindings.classes, objects: bindings.objects, constants: wrong)),
        files: runtimeFiles);
    expect(build.success, isFalse);
    expect(build.rawOutput, contains('MSBFIRST: the C++ value of MSBFIRST is not 0'));
  });

  test('a @CppPrint class must derive from Print: SoftwareSerial does, Servo does not', () async {
    gate.check();
    ApiClass printing(String name, String header) =>
        ApiClass(name, cppName: name, header: header, methods: const [], isPrint: true);
    final good = await compileSketch(
        'conformance_print', conformanceProbe(ApiBindings(classes: [printing('SoftwareSerial', 'SoftwareSerial.h')])));
    printOnFailure(good.rawOutput);
    expect(good.success, isTrue);
    final bad = await compileSketch(
        'conformance_no_print', conformanceProbe(ApiBindings(classes: [printing('Servo', 'Servo.h')])));
    expect(bad.success, isFalse);
    expect(bad.rawOutput, contains('Servo: @CppPrint, but Servo does not derive from Print'));
  });
}
