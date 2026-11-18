import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';

import '../test_paths.dart';

/// `-fwrapv` (docs/SUBSET.md "Building") must reach every arduino-cli build. `unodar build` and the Dart tests take
/// the properties from [UnoTarget.buildProperties] (`build_command_test` checks the call); the docs cannot, so this
/// keeps their copies identical, and `tool/check_arduino.sh` must build through `unodar build`.
void main() {
  final properties = const UnoTarget().buildProperties;

  test('the Uno is built with -fwrapv at compile and link time', () {
    expect(properties, [
      'compiler.c.extra_flags=-fwrapv',
      'compiler.cpp.extra_flags=-fwrapv',
      'compiler.c.elf.extra_flags=-fwrapv',
    ]);
  });

  final copies = {
    'docs/SUBSET.md': fromPackage('..', '..', 'docs', 'SUBSET.md'),
  };
  copies.forEach((name, path) {
    test('$name passes every build property', () {
      final text = File(path).readAsStringSync();
      for (final property in properties) {
        expect(text, contains('--build-property $property'), reason: '$name must pass $property');
      }
    });
  });

  test('tool/check_arduino.sh builds with `unodar build`, which passes the properties', () {
    final script = File(fromPackage('..', '..', 'tool', 'check_arduino.sh')).readAsStringSync();
    expect(script, contains('unodar build "examples/'));
    expect(script, isNot(contains('--cpp-only')));
  });
}
