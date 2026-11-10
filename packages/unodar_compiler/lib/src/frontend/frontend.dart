import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' as analyzer;
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostics.dart';

/// A fully resolved Dart file, ready for validation.
final class ResolvedSource {
  const ResolvedSource({required this.displayName, required this.unit});

  /// Basename of the source file, used in diagnostics and `#line` directives.
  final String displayName;

  /// The resolved AST. Elements and static types are populated.
  final CompilationUnit unit;

  LineInfo get lineInfo => unit.lineInfo;

  /// The 1-based location of [offset] in this file.
  SourceLocation locationOf(int offset) {
    final location = lineInfo.getLocation(offset);
    return SourceLocation(file: displayName, line: location.lineNumber, column: location.columnNumber);
  }
}

sealed class FrontendResult {
  const FrontendResult();
}

final class FrontendSuccess extends FrontendResult {
  const FrontendSuccess(this.source);

  final ResolvedSource source;
}

/// The file resolved but has Dart errors (E007). Validation is skipped: an AST with type or syntax errors would
/// produce misleading follow-on diagnostics.
final class FrontendFailure extends FrontendResult {
  const FrontendFailure(this.diagnostics);

  final List<Diagnostic> diagnostics;
}

/// The input could not be read at all (missing file, not a Dart file). This is a tooling/usage problem, not a
/// diagnostic in the user's code.
final class FrontendInputError extends FrontendResult {
  const FrontendInputError(this.message);

  final String message;
}

/// PRD §9.5 step 1: resolves a Dart file with `package:analyzer`.
///
/// Package resolution uses the `package_config.json` nearest to the file, exactly like `dart analyze`, so a user
/// project needs the usual `dart pub get` with a dependency on `unodar`.
final class Frontend {
  const Frontend();

  Future<FrontendResult> resolve(String path) async {
    final absolute = p.normalize(p.absolute(path));
    if (p.extension(absolute) != '.dart') return FrontendInputError('not a Dart file: $path');
    if (!File(absolute).existsSync()) return FrontendInputError('file not found: $path');

    final collection = AnalysisContextCollection(includedPaths: [absolute]);
    try {
      final result = await collection.contextFor(absolute).currentSession.getResolvedUnit(absolute);
      if (result is! ResolvedUnitResult) return FrontendInputError('could not analyze $path (${result.runtimeType})');

      final source = ResolvedSource(displayName: p.basename(absolute), unit: result.unit);
      final errors = [
        for (final d in result.diagnostics)
          if (d.severity == analyzer.Severity.error)
            Diagnostics.analysisError(d.message.trim(), source.locationOf(d.offset)),
      ];
      return errors.isEmpty ? FrontendSuccess(source) : FrontendFailure(sortDiagnostics(errors));
    } finally {
      await collection.dispose();
    }
  }
}
