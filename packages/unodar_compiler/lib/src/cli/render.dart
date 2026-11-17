import 'dart:convert';

import '../diagnostics/diagnostics.dart';
import '../version.dart';
import 'new_project.dart';

/// The anchor of each code's section in `docs/DIAGNOSTICS.md`, as GitHub derives it from the heading.
/// `render_test` recomputes them from the headings, so a renamed section cannot leave a dead link.
const diagnosticAnchors = {
  'E001': 'e001-missing-required-setup-or-loop',
  'E002': 'e002-unsupported-statement-or-expression-kind',
  'E003': 'e003-call-to-a-function-that-is-not-part-of-the-supported-unodar-api',
  'E004': 'e004-unsupported-argument',
  'E005': 'e005-unsupported-top-level-declaration',
  'E006': 'e006-invalid-setuploop-signature',
  'E007': 'e007-dart-analysis-error-in-the-source-file',
  'E008': 'e008-unsupported-main',
  'E009': 'e009-unsupported-type',
  'E010': 'e010-constant-out-of-range',
  'E011': 'e011-unsupported-function-signature',
  'E012': 'e012-closure-or-function-value',
  'E013': 'e013-evaluation-order-differs-in-c',
  'E014': 'e014-reserved-name',
  'E015': 'e015-top-level-initializer-is-not-a-compile-time-constant',
  'E016': 'e016-recursive-function',
  'E017': 'e017-invalid-binding-class-or-interop-annotation',
  'E018': 'e018-object-misuse',
  'E019': 'e019-cpp-misuse',
  'E020': 'e020-heap-allocation-in-cpp',
  'E021': 'e021-widget-program-shape',
  'E022': 'e022-widget-rules',
  'E023': 'e023-delay-in-a-widget-callback',
  'E024': 'e024-signal-misuse',
  'E025': 'e025-reactive-cycle',
  'E026': 'e026-computed-rules',
  'E027': 'e027-class-rules',
  'E028': 'e028-enum-rules',
};

/// The documentation of [code], at this compiler's release tag (D8).
String diagnosticLink(DiagnosticCode code) =>
    '$unodarRepository/blob/v$unodarVersion/docs/DIAGNOSTICS.md#${diagnosticAnchors[code.id]}';

/// [diagnostic] for a terminal (CLI only; goldens and docs keep [Diagnostic.format]): the header, the source line
/// with a caret under the column, the help, and a link to the code's documentation. [source] is the text of the
/// file the diagnostic is in (no snippet without it). [color] adds ANSI colours.
String renderDiagnostic(Diagnostic diagnostic, {String? source, bool color = false}) {
  String paint(String text, String code) => color ? '\x1B[${code}m$text\x1B[0m' : text;
  final location = diagnostic.location;
  final lines = source == null ? const <String>[] : const LineSplitter().convert(source);
  final out = StringBuffer()
    ..writeln('${paint('$location:', '1')} ${paint('error[${diagnostic.code.id}]', '1;31')}: '
        '${paint(diagnostic.message, '1')}');
  if (location.line >= 1 && location.line <= lines.length) {
    final number = '${location.line}';
    final gutter = ' ' * number.length;
    final text = lines[location.line - 1].replaceAll('\t', ' ');
    final column = (location.column - 1).clamp(0, text.length);
    out
      ..writeln(paint('$gutter |', '34'))
      ..writeln('${paint('$number |', '34')} $text')
      ..writeln('${paint('$gutter |', '34')} ${' ' * column}${paint('^', '1;31')}');
  }
  out
    ..writeln('  = ${paint('help', '1')}: ${diagnostic.suggestion}')
    ..write('  = see: ${diagnosticLink(diagnostic.code)}');
  return '$out';
}
