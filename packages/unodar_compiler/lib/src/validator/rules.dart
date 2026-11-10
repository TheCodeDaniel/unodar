import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_registry.dart';
import '../api/api_resolution.dart';
import '../diagnostics/diagnostics.dart';
import '../frontend/frontend.dart';
import 'describe.dart';

/// Shared state for one validation run. Rules only ever *add* diagnostics; none of them stops the run, so the user
/// sees every problem at once (PRD §9.5 step 2).
final class ValidationContext {
  ValidationContext(this.source, this.api);

  final ResolvedSource source;
  final ApiRegistry api;
  final List<Diagnostic> diagnostics = [];

  void report(Diagnostic diagnostic) => diagnostics.add(diagnostic);

  SourceLocation at(SyntacticEntity node) => source.locationOf(node.offset);
}

/// One independent subset check (PRD §9.10 "Validator rules are composable").
///
/// Each rule owns one concern. Phase 2 relaxes the subset by replacing or removing individual rules (for example,
/// a new statement rule that accepts `if`), not by editing a monolithic walker.
abstract interface class ValidationRule {
  void check(CompilationUnit unit, ValidationContext context);
}

/// The two required entry points.
const entryPointNames = ['setup', 'loop'];

/// Top-level `setup`/`loop` function declarations in source order (whatever their signature).
Iterable<FunctionDeclaration> entryPoints(CompilationUnit unit) =>
    unit.declarations.whereType<FunctionDeclaration>().where((f) => entryPointNames.contains(f.name.lexeme));

/// The statements of every entry point with a block body. Entry points with any other body are E006 already.
Iterable<Statement> entryPointStatements(CompilationUnit unit) sync* {
  for (final function in entryPoints(unit)) {
    final body = function.functionExpression.body;
    if (body is BlockFunctionBody) yield* body.block.statements;
  }
}

/// The API-call candidates inside entry points: statements of the form `name(args);`. Anything else is E002.
Iterable<MethodInvocation> entryPointCalls(CompilationUnit unit) sync* {
  for (final statement in entryPointStatements(unit)) {
    if (statement case ExpressionStatement(expression: final MethodInvocation call)) yield call;
  }
}

/// Offsets of the names of unresolved, target-less calls written as statements in setup/loop (`tone(8, 440);`).
///
/// [ApiCallRule] reports each of these as E003, so the compiler lets the analyzer's error at the same offset through
/// to validation instead of stopping with E007.
Set<int> unresolvedEntryPointCallOffsets(CompilationUnit unit) => {
      for (final call in entryPointCalls(unit))
        if (call.target == null && call.methodName.element == null) call.methodName.offset,
    };

/// Only `import 'package:unodar/unodar.dart';` (unprefixed) is allowed. `library;` is harmless and allowed.
/// Unresolvable imports never reach this rule: they are analyzer errors (E007).
final class DirectiveRule implements ValidationRule {
  const DirectiveRule();

  static const allowedImport = 'package:unodar/unodar.dart';

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final directive in unit.directives) {
      final problem = switch (directive) {
        LibraryDirective() => null,
        ImportDirective(:final uri) when uri.stringValue != allowedImport => "an import of '${uri.stringValue}'",
        ImportDirective(prefix: _?) => 'a prefixed import (`as …`)',
        ImportDirective(deferredKeyword: _?) => 'a deferred import',
        ImportDirective() => null,
        ExportDirective() => 'an export directive',
        PartDirective() || PartOfDirective() => 'a part directive',
      };
      if (problem != null) context.report(Diagnostics.unsupportedDeclaration(problem, context.at(directive)));
    }
  }
}

/// Every top-level declaration must be `setup` or `loop` (E005); `main` is reserved (E008); both entry points must
/// exist (E001).
final class TopLevelDeclarationRule implements ValidationRule {
  const TopLevelDeclarationRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final declared = <String>{};
    for (final declaration in unit.declarations) {
      final start = declaration.firstTokenAfterCommentAndMetadata;
      switch (declaration) {
        case FunctionDeclaration(:final name) when entryPointNames.contains(name.lexeme):
          declared.add(name.lexeme);
        case FunctionDeclaration(:final name) when name.lexeme == 'main':
          context.report(Diagnostics.reservedMain(context.at(name)));
        case FunctionDeclaration(:final name, isGetter: true):
          context
              .report(Diagnostics.unsupportedDeclaration("a top-level getter ('${name.lexeme}')", context.at(start)));
        case FunctionDeclaration(:final name, isSetter: true):
          context
              .report(Diagnostics.unsupportedDeclaration("a top-level setter ('${name.lexeme}')", context.at(start)));
        case FunctionDeclaration(:final name):
          context.report(Diagnostics.unsupportedDeclaration("a function ('${name.lexeme}')", context.at(start)));
        case TopLevelVariableDeclaration(:final variables):
          final names = variables.variables.map((v) => v.name.lexeme).join("', '");
          context.report(Diagnostics.unsupportedDeclaration("a top-level variable ('$names')", context.at(start)));
        case ClassDeclaration():
          context.report(Diagnostics.unsupportedDeclaration('a class', context.at(start)));
        case EnumDeclaration():
          context.report(Diagnostics.unsupportedDeclaration('an enum', context.at(start)));
        case MixinDeclaration():
          context.report(Diagnostics.unsupportedDeclaration('a mixin', context.at(start)));
        case ExtensionDeclaration() || ExtensionTypeDeclaration():
          context.report(Diagnostics.unsupportedDeclaration('an extension', context.at(start)));
        case TypeAlias():
          context.report(Diagnostics.unsupportedDeclaration('a typedef', context.at(start)));
        default:
          context.report(Diagnostics.unsupportedDeclaration('this declaration', context.at(start)));
      }
    }
    for (final name in entryPointNames) {
      if (!declared.contains(name)) {
        context.report(Diagnostics.missingEntryPoint(name, context.source.locationOf(0)));
      }
    }
  }
}

/// `setup` and `loop` must be exactly `void name() { ... }` (E006).
final class EntryPointSignatureRule implements ValidationRule {
  const EntryPointSignatureRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final function in entryPoints(unit)) {
      final expression = function.functionExpression;
      final body = expression.body;
      final returnType = function.returnType;
      final problems = [
        if (function.isGetter) 'it is declared as a getter',
        if (function.isSetter) 'it is declared as a setter',
        if (returnType == null)
          'it has no return type'
        else if (returnType.type is! VoidType)
          'it returns ${returnType.toSource()}',
        if (expression.typeParameters != null) 'it has type parameters',
        if (expression.parameters?.parameters.isNotEmpty ?? false) 'it takes parameters',
        if (body.isAsynchronous) 'it is async',
        if (body.isGenerator) 'it is a generator',
        if (body is ExpressionFunctionBody) 'it uses an expression body (`=>`)',
        if (body is EmptyFunctionBody) 'it has no body',
      ];
      if (problems.isNotEmpty) {
        context.report(
            Diagnostics.invalidEntrySignature(function.name.lexeme, englishList(problems), context.at(function.name)));
      }
    }
  }
}

/// Inside `setup`/`loop`, every statement must be a single call expression statement (E002).
final class StatementRule implements ValidationRule {
  const StatementRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final statement in entryPointStatements(unit)) {
      if (statement case ExpressionStatement(expression: MethodInvocation())) continue;
      context.report(Diagnostics.unsupportedStatement(describeStatement(statement), context.at(statement)));
    }
  }
}

/// Every call must resolve to a supported unodar API function (E003).
final class ApiCallRule implements ValidationRule {
  const ApiCallRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final call in entryPointCalls(unit)) {
      if (context.api.resolveCall(call) != null) continue;
      final target = call.target;
      final name = target == null ? call.methodName.name : '${target.toSource()}.${call.methodName.name}';
      context.report(Diagnostics.unknownFunction(name, context.api.functionNames, context.at(call.methodName)));
    }
  }
}

/// Arguments to API calls must be integer literals or unodar constants (E004).
///
/// Arguments of calls that already failed [ApiCallRule] are not checked: the call is wrong as a whole, and
/// reporting its arguments too would be noise.
final class ArgumentRule implements ValidationRule {
  const ArgumentRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final call in entryPointCalls(unit)) {
      if (context.api.resolveCall(call) == null) continue;
      for (final argument in call.argumentList.arguments) {
        if (argument is IntegerLiteral && argument.value != null) continue;
        if (argument is Expression && context.api.resolveConstant(argument) != null) continue;
        final what = argument is Expression ? describeExpression(argument) : 'a named argument';
        context.report(Diagnostics.unsupportedArgument(what, context.at(argument)));
      }
    }
  }
}
