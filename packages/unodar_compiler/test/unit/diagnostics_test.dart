import 'package:test/test.dart';
import 'package:unodar_compiler/src/diagnostics/diagnostics.dart';

void main() {
  const at = SourceLocation(file: 'blink.dart', line: 5, column: 3);
  const api = ['pinMode', 'digitalWrite', 'delay'];

  group('Diagnostic.format', () {
    test('matches the PRD §9.6 header shape and puts the suggestion on a help line', () {
      final d = Diagnostics.unknownFunction('tone', api, at);
      expect(
        d.format(),
        "blink.dart:5:3: error[E003]: unknown function 'tone'. "
        'Only pinMode, digitalWrite, and delay are supported in this version.\n'
        '  = help: Remove this call. More Arduino functions arrive in a later phase; see docs/SUBSET.md.',
      );
    });
  });

  group('registry', () {
    test('codes are E001..E008, unique, and in order', () {
      expect(DiagnosticCode.values.map((c) => c.id), [for (var i = 1; i <= 8; i++) 'E00$i']);
    });

    test('every code has a non-empty summary for docs/DIAGNOSTICS.md', () {
      for (final code in DiagnosticCode.values) {
        expect(code.summary, isNotEmpty, reason: code.id);
      }
    });

    test('every factory produces a diagnostic with a suggestion', () {
      final all = [
        Diagnostics.missingEntryPoint('loop', at),
        Diagnostics.unsupportedStatement('an if statement', at),
        Diagnostics.unknownFunction('tone', api, at),
        Diagnostics.unsupportedArgument('a variable reference', at),
        Diagnostics.unsupportedDeclaration('a top-level variable', at),
        Diagnostics.invalidEntrySignature('setup', 'it returns int', at),
        Diagnostics.analysisError("The argument type 'String' can't be assigned to 'int'.", at),
        Diagnostics.reservedMain(at),
      ];
      expect(all.map((d) => d.code), DiagnosticCode.values, reason: 'one factory per code, in code order');
      for (final d in all) {
        expect(d.suggestion, isNotEmpty, reason: d.code.id);
        expect(d.severity, Severity.error);
      }
    });
  });

  test('sortDiagnostics orders by line, column, then code for deterministic output', () {
    SourceLocation loc(int line, int col) => SourceLocation(file: 'a.dart', line: line, column: col);
    final sorted = sortDiagnostics([
      Diagnostics.reservedMain(loc(9, 1)),
      Diagnostics.unknownFunction('tone', api, loc(2, 5)),
      Diagnostics.unsupportedArgument('x', loc(2, 5)),
      Diagnostics.unknownFunction('tone', api, loc(2, 1)),
    ]);
    expect(sorted.map((d) => '${d.location.line}:${d.location.column}:${d.code.id}'), [
      '2:1:E003',
      '2:5:E003',
      '2:5:E004',
      '9:1:E008',
    ]);
  });
}
