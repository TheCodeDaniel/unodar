import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';

import '../test_paths.dart';

/// `-fwrapv` (docs/SUBSET.md "Building") must reach every arduino-cli build. The Dart tests take the properties
/// from [UnoTarget.buildProperties]; the shell script and the README cannot, so this keeps their copies identical.
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
    'tool/check_arduino.sh': fromPackage('..', '..', 'tool', 'check_arduino.sh'),
    'README.md': fromPackage('..', '..', 'README.md'),
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
}
