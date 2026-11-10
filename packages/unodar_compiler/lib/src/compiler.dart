import 'api/api_registry.dart';
import 'diagnostics/diagnostics.dart';
import 'emitter/emitter.dart';
import 'frontend/frontend.dart';
import 'lowering/lowering.dart';
import 'validator/validator.dart';

sealed class CompileResult {
  const CompileResult();
}

/// The sketch compiled. [cpp] is the full `.ino` text.
final class CompileSuccess extends CompileResult {
  const CompileSuccess({required this.sourceName, required this.cpp});

  final String sourceName;
  final String cpp;
}

/// The user's source has problems (exit code 1).
final class CompileFailure extends CompileResult {
  const CompileFailure(this.diagnostics);

  final List<Diagnostic> diagnostics;
}

/// The input could not be read (exit code 2).
final class CompileInputError extends CompileResult {
  const CompileInputError(this.message);

  final String message;
}

/// The whole pipeline (PRD §9.5): frontend → validator → lowering → emitter.
///
/// Stages are injected so tests can exercise one stage at a time and later phases can swap targets/registries.
final class Compiler {
  Compiler({ApiRegistry? api, this.target = const UnoTarget(), this.frontend = const Frontend()})
      : api = api ?? ApiRegistry.phase1();

  final ApiRegistry api;
  final Target target;
  final Frontend frontend;

  Future<CompileResult> compile(String path) async {
    final ResolvedSource source;
    switch (await frontend.resolve(path)) {
      case FrontendSuccess(source: final resolved):
        source = resolved;
      case FrontendFailure(:final diagnostics):
        return CompileFailure(diagnostics);
      case FrontendInputError(:final message):
        return CompileInputError(message);
    }
    final diagnostics = Validator(api: api).validate(source);
    if (diagnostics.isNotEmpty) return CompileFailure(diagnostics);
    final program = Lowering(api).lower(source);
    return CompileSuccess(sourceName: source.displayName, cpp: CppEmitter(target).emit(program));
  }
}
