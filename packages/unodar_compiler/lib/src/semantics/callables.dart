import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';

import 'classes.dart';
import 'elements.dart';

/// A compiled function with a declaration of its own: a top-level function, or a method or getter of one of the
/// user's classes (docs/SUBSET.md "Your own classes"). Rules that check signatures, types, names and the call graph
/// (E011, E009, E014, E016, E018, E022–E025) treat both alike through this view.
final class Callable {
  Callable.function(FunctionDeclaration this.function)
      : method = null,
        owner = null;

  Callable.method(MethodDeclaration this.method, ClassDeclaration this.owner) : function = null;

  final FunctionDeclaration? function;
  final MethodDeclaration? method;

  /// The class of a method, or null for a top-level function.
  final ClassDeclaration? owner;

  AstNode get declaration => (function ?? method)!;
  Token get name => function != null ? function!.name : method!.name;
  ExecutableElement? get element =>
      function != null ? function!.declaredFragment?.element : method!.declaredFragment?.element;
  FunctionBody get body => function != null ? function!.functionExpression.body : method!.body;
  FormalParameterList? get parameters =>
      function != null ? function!.functionExpression.parameters : method!.parameters;
  TypeAnnotation? get returnType => function != null ? function!.returnType : method!.returnType;
  TypeParameterList? get typeParameters =>
      function != null ? function!.functionExpression.typeParameters : method!.typeParameters;
  bool get isGetter => method?.isGetter ?? false;
  int get offset => declaration.offset;

  /// `blink`, or `Meter.add` for a method, as call paths and messages show it.
  String get displayName => owner == null ? name.lexeme : '${owner!.namePart.typeName.lexeme}.${name.lexeme}';
}

/// The methods and getters of the user's classes that are compiled, in source order: instance members that are not
/// setters, operators, `external`, or overrides of `Object`'s members (all E027), in classes that extend nothing.
Iterable<(MethodDeclaration, ClassDeclaration)> compiledMethods(CompilationUnit unit) sync* {
  for (final declaration in userClassDeclarations(unit)) {
    if (declaration.extendsClause != null) continue;
    for (final method in declaration.body.members.whereType<MethodDeclaration>()) {
      if (method.isSetter || method.isOperator || method.isStatic || method.externalKeyword != null) continue;
      if (objectMemberNames.contains(method.name.lexeme)) continue;
      yield (method, declaration);
    }
  }
}

/// `Object`'s members, which a class may not override (E027).
const objectMemberNames = {'toString', 'hashCode', 'noSuchMethod', 'runtimeType'};

/// Every compiled function and method, in source order.
List<Callable> compiledCallables(CompilationUnit unit) => [
      for (final function in compiledFunctions(unit)) Callable.function(function),
      for (final (method, owner) in compiledMethods(unit)) Callable.method(method, owner),
    ]..sort((a, b) => a.offset.compareTo(b.offset));

/// The user function, method or getter [node] calls, or null: a call of a top-level function, a method call on an
/// object or on `this` (explicit or implicit), or a read of an explicit getter (`meter.big`, `big` in a method).
ExecutableElement? calleeOf(AstNode node) {
  switch (node) {
    case MethodInvocation():
      if (userFunctionOf(node) case final function?) return function;
      final element = node.methodName.element;
      return element is MethodElement && !element.isStatic && isUserClass(element.enclosingElement) ? element : null;
    case PrefixedIdentifier(:final identifier):
      return _getter(identifier.element);
    case PropertyAccess(:final propertyName):
      return _getter(propertyName.element);
    case SimpleIdentifier() when node.parent is! PrefixedIdentifier && node.parent is! PropertyAccess:
      return node.parent is MethodInvocation && (node.parent as MethodInvocation).methodName == node
          ? null
          : _getter(node.element);
    default:
      return null;
  }
}

/// An explicit getter of a user class (not the implicit getter of a field).
GetterElement? _getter(Element? element) =>
    element is GetterElement && !element.isOriginVariable && !element.isStatic && isUserClass(element.enclosingElement)
        ? element
        : null;
