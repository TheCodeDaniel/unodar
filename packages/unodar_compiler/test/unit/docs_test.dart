import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/diagnostics/diagnostics.dart';

import '../test_paths.dart';

/// Keeps docs/DIAGNOSTICS.md honest (PRD §9.9 criterion 4): every registered code is documented with a section.
void main() {
  final doc = File(fromPackage('..', '..', 'docs', 'DIAGNOSTICS.md')).readAsStringSync();

  for (final code in DiagnosticCode.values) {
    test('${code.id} is documented with an example', () {
      final heading = RegExp('^## ${code.id}: ', multiLine: true);
      expect(doc, matches(heading), reason: 'add a "## ${code.id}: …" section to docs/DIAGNOSTICS.md');
      final section = doc.substring(doc.indexOf(heading)).split(RegExp(r'^## ', multiLine: true))[1];
      expect(section, contains('error[${code.id}]'), reason: 'the ${code.id} section needs an example diagnostic');
    });
  }
}
