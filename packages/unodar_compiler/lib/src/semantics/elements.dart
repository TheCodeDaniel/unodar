import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import '../api/api_resolution.dart';

/// What a name in the user's code refers to, for the constructs Phase 2 supports.
sealed class Reference {
  const Reference();
}

/// A local variable or a parameter.
final class LocalReference extends Reference {
  const LocalReference(this.element);

  final VariableElement element;
}

/// A top-level variable declared in the user's file.
final class GlobalReference extends Reference {
  const GlobalReference(this.element);

  final TopLevelVariableElement element;

  /// Assignable, so a call could change it between two reads (E013).
  bool get isMutable => !element.isConst && !element.isFinal;
}

/// A constant declared in `package:unodar` (`HIGH`, …).
final class UnodarConstantReference extends Reference {
  const UnodarConstantReference(this.element);

  final TopLevelVariableElement element;
}

/// A top-level function, used as a value instead of being called (E012).
final class FunctionValueReference extends Reference {
  const FunctionValueReference(this.element);

  final ExecutableElement element;
}

/// What [identifier] refers to, or null for anything else (type names, members, unresolved names).
Reference? referenceOf(SimpleIdentifier identifier) {
  final element = identifier.element;
  final variable = element is GetterElement ? element.variable : element;
  return switch (variable) {
    LocalVariableElement() || FormalParameterElement() => LocalReference(variable as VariableElement),
    TopLevelVariableElement() when isUnodarElement(variable) => UnodarConstantReference(variable),
    TopLevelVariableElement() => GlobalReference(variable),
    TopLevelFunctionElement() || LocalFunctionElement() => FunctionValueReference(variable as ExecutableElement),
    _ => null,
  };
}

/// The top-level function [call] invokes if it is declared in the user's file (not the unodar API), else null.
TopLevelFunctionElement? userFunctionOf(MethodInvocation call) {
  if (call.target != null) return null;
  final element = call.methodName.element;
  if (element is! TopLevelFunctionElement || isUnodarElement(element)) return null;
  return element.library.uri.scheme == 'dart' ? null : element;
}

/// Top-level functions that are compiled: everything except `main` (E008) and getters/setters (E005).
Iterable<FunctionDeclaration> compiledFunctions(CompilationUnit unit) => unit.declarations
    .whereType<FunctionDeclaration>()
    .where((f) => f.name.lexeme != 'main' && !f.isGetter && !f.isSetter);

/// The user's top-level variables, in source order.
Iterable<VariableDeclaration> topLevelVariables(CompilationUnit unit) =>
    unit.declarations.whereType<TopLevelVariableDeclaration>().expand((d) => d.variables.variables);

/// The two required entry points.
const entryPointNames = ['setup', 'loop'];

bool isEntryPoint(FunctionDeclaration function) => entryPointNames.contains(function.name.lexeme);
