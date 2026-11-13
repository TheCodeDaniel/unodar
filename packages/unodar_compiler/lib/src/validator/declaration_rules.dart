import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import '../diagnostics/diagnostics.dart';
import '../ir/ir.dart';
import '../semantics/elements.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import 'rules.dart';

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

/// Top-level functions and variables are allowed; `main` is reserved (E008); everything else is E005; both entry
/// points must exist (E001).
final class TopLevelDeclarationRule implements ValidationRule {
  const TopLevelDeclarationRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final declared = <String>{};
    for (final declaration in unit.declarations) {
      final start = declaration.firstTokenAfterCommentAndMetadata;
      void unsupported(String what, {String? suggestion}) =>
          context.report(Diagnostics.unsupportedDeclaration(what, context.at(start), suggestion: suggestion));
      switch (declaration) {
        case FunctionDeclaration(:final name) when name.lexeme == 'main':
          context.report(Diagnostics.reservedMain(context.at(name)));
        case FunctionDeclaration(:final name, isGetter: true):
          unsupported("a top-level getter ('${name.lexeme}')");
        case FunctionDeclaration(:final name, isSetter: true):
          unsupported("a top-level setter ('${name.lexeme}')");
        case FunctionDeclaration(:final name):
          declared.add(name.lexeme);
        case TopLevelVariableDeclaration(:final variables, :final externalKeyword):
          final names = variables.variables.map((v) => v.name.lexeme).join("', '");
          if (variables.isLate) {
            unsupported("a late variable ('$names')",
                suggestion: 'Remove `late` and give the variable a constant initializer.');
          } else if (externalKeyword != null &&
              !variables.variables.every((v) => bindingClassOf(v.declaredFragment?.element.type) != null)) {
            unsupported("an external variable ('$names') whose type is not a binding class");
          }
        case ClassDeclaration(:final declaredFragment)
            when declaredFragment != null && hasInteropAnnotation(declaredFragment.element, 'CppClass'):
          break; // A binding class: BindingClassRule checks it (E017).
        case ClassDeclaration():
          unsupported('a class without @CppClass',
              suggestion: "Remove this declaration, or annotate it with `@CppClass('CppName')` if it describes a C++ "
                  'class; see docs/SUBSET.md.');
        case EnumDeclaration():
          unsupported('an enum');
        case MixinDeclaration():
          unsupported('a mixin');
        case ExtensionDeclaration() || ExtensionTypeDeclaration():
          unsupported('an extension');
        case TypeAlias():
          unsupported('a typedef');
        default:
          unsupported('this declaration');
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
    for (final function in compiledFunctions(unit).where(isEntryPoint)) {
      final expression = function.functionExpression;
      final body = expression.body;
      final returnType = function.returnType;
      final problems = [
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

/// User functions take only required, positional, explicitly typed parameters; no generics, no async (E011).
final class FunctionSignatureRule implements ValidationRule {
  const FunctionSignatureRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final function in compiledFunctions(unit).where((f) => !isEntryPoint(f))) {
      final expression = function.functionExpression;
      final parameters = expression.parameters?.parameters ?? const <FormalParameter>[];
      final body = expression.body;
      final problems = [
        if (expression.typeParameters != null) 'type parameters',
        if (parameters.any((p) => p.isOptionalPositional)) 'optional positional parameters',
        if (parameters.any((p) => p.isNamed)) 'named parameters',
        if (parameters.any((p) => p.defaultClause != null)) 'a default value',
        for (final p in parameters)
          if (p.functionTypedSuffix != null)
            "a function-typed parameter ('${p.name?.lexeme}')"
          else if (!p.isExplicitlyTyped)
            "an untyped parameter ('${p.name?.lexeme}')",
        if (function.returnType == null) 'no return type',
        if (body.isAsynchronous) 'an async body',
        if (body.isGenerator) 'a generator body',
        if (body is EmptyFunctionBody) 'no body (it is external)',
      ];
      if (problems.isNotEmpty) {
        context.report(Diagnostics.unsupportedSignature(
            function.name.lexeme, 'it has ${englishList(problems)}', context.at(function.name)));
      }
    }
  }
}

/// Declared types must be supported (E009). Inferred types are checked through their initializer expressions by
/// [ExpressionTypeRule], so each problem is reported once. Generic functions are E011 and skipped here.
final class DeclaredTypeRule implements ValidationRule {
  const DeclaredTypeRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final declaration in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      _variables(declaration.variables, context);
    }
    for (final function in compiledFunctions(unit)) {
      final expression = function.functionExpression;
      if (expression.typeParameters != null) continue;
      final returnType = function.returnType;
      if (returnType != null) _annotation(returnType, context, allowVoid: true);
      for (final parameter in expression.parameters?.parameters ?? const <FormalParameter>[]) {
        if (parameter.type case final type? when parameter.functionTypedSuffix == null) _annotation(type, context);
      }
      for (final statement in statementsIn(expression.body)) {
        switch (statement) {
          case VariableDeclarationStatement(:final variables):
            _variables(variables, context);
          case ForStatement(forLoopParts: ForPartsWithDeclarations(:final variables)):
            _variables(variables, context);
          default:
        }
      }
    }
  }

  void _variables(VariableDeclarationList list, ValidationContext context) {
    final annotation = list.type;
    if (isBindingType(annotation?.type)) return; // E018 decides where a binding type may appear.
    if (annotation != null) {
      _annotation(annotation, context);
      return;
    }
    // `var x;`: no annotation and nothing to infer from, so the type is dynamic.
    for (final variable in list.variables) {
      final type = variable.declaredFragment?.element.type;
      if (variable.initializer == null && type != null && irTypeOf(type) == null) {
        context.report(Diagnostics.unsupportedType(displayType(type), context.at(variable.name)));
      }
    }
  }

  void _annotation(TypeAnnotation annotation, ValidationContext context, {bool allowVoid = false}) {
    final type = annotation.type;
    if (type == null || isBindingType(type)) return;
    final irType = irTypeOf(type);
    if (irType != null && (allowVoid || irType != IrType.void_)) return;
    context.report(typeDiagnostic(type, context.at(annotation)));
  }
}

/// The E009 diagnostic for an unsupported [type].
Diagnostic typeDiagnostic(DartType type, SourceLocation at, {bool isConditional = false}) {
  final display = displayType(type);
  if (isNullable(type)) return Diagnostics.nullableType(display, display.substring(0, display.length - 1), at);
  return Diagnostics.unsupportedType(display, at, isConditional: isConditional);
}
