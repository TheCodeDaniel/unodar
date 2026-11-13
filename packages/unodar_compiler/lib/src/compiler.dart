import 'api/api_registry.dart';
import 'api/binding_reader.dart';
import 'diagnostics/diagnostics.dart';
import 'emitter/emitter.dart';
import 'frontend/frontend.dart';
import 'lowering/lowering.dart';
import 'runtime/runtime_files.dart';
import 'validator/rules.dart';
import 'validator/validator.dart';

sealed class CompileResult {
  const CompileResult();
}

/// The sketch compiled. [cpp] is the full `.ino` text.
final class CompileSuccess extends CompileResult {
  const CompileSuccess({required this.sourceName, required this.cpp, this.files = const {}});

  final String sourceName;
  final String cpp;

  /// Files that belong next to the `.ino` in the sketch folder, by file name (`unodar_widgets.h` for a widget
  /// program). Empty for a plain `setup()`/`loop()` sketch.
  final Map<String, String> files;
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
      : api = api ?? ApiRegistry.core();

  final ApiRegistry api;
  final Target target;
  final Frontend frontend;

  Future<CompileResult> compile(String path) async {
    final ResolvedSource source;
    final List<AnalysisError> analysisErrors;
    switch (await frontend.resolve(path)) {
      case FrontendSuccess(source: final resolved, analysisErrors: final errors):
        source = resolved;
        analysisErrors = errors;
      case FrontendInputError(:final message):
        return CompileInputError(message);
    }

    // Analyzer errors normally stop compilation (E007): validating a broken AST yields misleading diagnostics.
    // The one exception is a call to an undefined function written as a plain statement, e.g.
    // `tone(8, 440);`. The analyzer calls that an undefined name, but the user's real problem is "not part of the
    // unodar API", which the validator reports as E003 with a better suggestion.
    final unresolvedCalls = unresolvedCallStatementOffsets(source.unit);
    final fatal = analysisErrors.where((e) => !unresolvedCalls.contains(e.offset));
    if (fatal.isNotEmpty) return CompileFailure(sortDiagnostics(analysisErrors.map((e) => e.diagnostic)));

    final (programApi, unodarApi) = _registryFor(source);
    final diagnostics =
        Validator(api: programApi, target: target, unodarNames: unodarApi.reservedNames).validate(source);
    if (diagnostics.isNotEmpty) return CompileFailure(diagnostics);
    // Defensive: never let a deferred analyzer error through just because no rule explained it.
    if (analysisErrors.isNotEmpty) return CompileFailure(sortDiagnostics(analysisErrors.map((e) => e.diagnostic)));
    final program = Lowering(programApi).lower(source);
    return CompileSuccess(
        sourceName: source.displayName, cpp: CppEmitter(target).emit(program), files: runtimeFilesFor(program));
  }

  /// The registry for one program: [api] plus the bindings `package:unodar` exports (Wire, Servo), and that plus the
  /// program's own binding classes and objects. User classes with E017 problems, or whose Dart name `package:unodar`
  /// already uses (E014), are left out; the validator reports them.
  (ApiRegistry program, ApiRegistry unodar) _registryFor(ResolvedSource source) {
    final library = source.unit.declaredFragment!.element;
    final reader = BindingReader(target);
    final unodar = api.withBindings(reader.readImportedUnodar(library));
    final valid = {
      for (final declaration in bindingClassDeclarations(source.unit))
        if (bindingClassDiagnostics(declaration, source, target).isEmpty &&
            !unodar.reservedNames.contains(declaration.namePart.typeName.lexeme))
          declaration.declaredFragment!.element,
    };
    final own = reader.readLibrary(library, include: valid.contains);
    final objects = [
      for (final object in own.objects)
        if (!unodar.reservedNames.contains(object.dartName)) object
    ];
    return (unodar.withBindings(ApiBindings(classes: own.classes, objects: objects)), unodar);
  }
}
