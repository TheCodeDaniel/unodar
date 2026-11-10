import 'codes.dart';

enum Severity { error }

/// A 1-based position in a source file. [file] is the display name (the basename), not an absolute path, so that
/// diagnostics and goldens are identical on every machine.
final class SourceLocation {
  const SourceLocation({required this.file, required this.line, required this.column});

  final String file;
  final int line;
  final int column;

  @override
  String toString() => '$file:$line:$column';
}

/// One problem found in the user's source. Construct via the factories in `Diagnostics` (messages.dart) so that
/// all wording lives in one place.
final class Diagnostic {
  const Diagnostic({
    required this.code,
    required this.location,
    required this.message,
    required this.suggestion,
    this.severity = Severity.error,
  });

  final DiagnosticCode code;
  final Severity severity;
  final SourceLocation location;
  final String message;
  final String suggestion;

  /// Renders as `file:line:col: error[E003]: message` followed by an indented `= help:` line.
  ///
  /// The header line is the PRD §9.6 format and is what editors and CI parse; the suggestion sits on its own line
  /// so it never makes the header ambiguous.
  String format() => '$location: ${severity.name}[${code.id}]: $message\n  = help: $suggestion';

  @override
  String toString() => format();
}

/// Orders diagnostics by line, column, then code. The validator walks the AST in source order already, but sorting
/// makes the output deterministic regardless of which rule found a problem first.
List<Diagnostic> sortDiagnostics(Iterable<Diagnostic> diagnostics) {
  return diagnostics.toList()
    ..sort((a, b) {
      final byLine = a.location.line.compareTo(b.location.line);
      if (byLine != 0) return byLine;
      final byColumn = a.location.column.compareTo(b.location.column);
      if (byColumn != 0) return byColumn;
      return a.code.index.compareTo(b.code.index);
    });
}
