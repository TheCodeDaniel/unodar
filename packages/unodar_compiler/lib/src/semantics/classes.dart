import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';

/// The user's own classes (docs/SUBSET.md "Your own classes"): every class declared in the user's file without
/// `@CppClass`. Their objects are statically allocated places, used only through their fields and methods. Shared by
/// the validator and the lowering, so "what is an object" is defined once.

/// The user's class declarations (not binding classes), in source order.
Iterable<ClassDeclaration> userClassDeclarations(CompilationUnit unit) => unit.declarations
    .whereType<ClassDeclaration>()
    .where((c) => c.declaredFragment != null && !hasInteropAnnotation(c.declaredFragment!.element, 'CppClass'));

/// Whether [element] is a class of the user's own: declared outside `package:unodar` and the Dart SDK, and not a
/// binding class. The program is a single file (other imports are E005), so that is the user's file.
bool isUserClass(Element? element) =>
    element is ClassElement &&
    !isUnodarElement(element) &&
    element.library.uri.scheme != 'dart' &&
    !hasInteropAnnotation(element, 'CppClass');

/// The user class [type] names, or null.
ClassElement? userClassOf(DartType? type) =>
    type is InterfaceType && isUserClass(type.element) ? type.element as ClassElement : null;

/// [expression] if it creates an object of a user class (`Counter(2, scale: 3)`), else null.
InstanceCreationExpression? objectCreation(Expression? expression) =>
    expression is InstanceCreationExpression && userClassOf(expression.staticType) != null ? expression : null;

/// The creation of a top-level object (`final left = Counter(2);`): a top-level `final` (not `const`, not `late`)
/// whose initializer calls its class's unnamed constructor. Null for anything else, which E018 reports.
InstanceCreationExpression? topLevelObject(VariableDeclaration variable) {
  final list = variable.parent;
  if (list is! VariableDeclarationList || list.parent is! TopLevelVariableDeclaration) return null;
  if (!list.isFinal || list.isConst || list.isLate) return null;
  final creation = objectCreation(variable.initializer);
  if (creation == null || creation.constructorName.name != null) return null;
  final declared = variable.declaredFragment?.element.type;
  return userClassOf(declared) == userClassOf(creation.staticType) ? creation : null;
}

/// An instance field of a user class read or written through a top-level object: `left.count`.
final class FieldAccess {
  const FieldAccess(this.object, this.field);

  /// The object's top-level variable.
  final TopLevelVariableElement object;
  final FieldElement field;

  bool get isMutable => !field.isFinal && !field.isConst;
}

/// [expression] as a field access (`left.count`, also as an assignment target), or null. The object must be a
/// top-level variable of a user class; whether that variable is an accepted object is E018's question.
FieldAccess? fieldAccessOf(Expression expression) {
  final (SimpleIdentifier? target, SimpleIdentifier? property) = switch (expression) {
    PrefixedIdentifier(:final prefix, :final identifier) => (prefix, identifier),
    PropertyAccess(target: final SimpleIdentifier target, :final propertyName) => (target, propertyName),
    _ => (null, null),
  };
  if (target == null || property == null || userClassOf(target.staticType) == null) return null;
  final object = switch (target.element) {
    final GetterElement getter => getter.variable,
    final other => other,
  };
  if (object is! TopLevelVariableElement) return null;
  final field = _fieldOf(property.element) ?? _fieldOf(_writeElementOf(expression));
  if (field == null || field.isStatic || !isUserClass(field.enclosingElement)) return null;
  return FieldAccess(object, field);
}

/// The field behind [element]: the field itself, or its implicit getter or setter. An explicit getter (`get x`) has
/// a synthetic field, which is not a field here.
FieldElement? _fieldOf(Element? element) {
  final field = switch (element) {
    final GetterElement getter when getter.isOriginVariable => getter.variable,
    final SetterElement setter when setter.isOriginVariable => setter.variable,
    final FieldElement field => field,
    _ => null,
  };
  return field is FieldElement && field.isOriginDeclaration ? field : null;
}

/// The element an assignment or `++`/`--` writes when [target] is its target (the target itself has none).
Element? _writeElementOf(Expression target) => switch (target.parent) {
      final AssignmentExpression a when a.leftHandSide == target => a.writeElement,
      final PrefixExpression p when p.operand == target => p.writeElement,
      final PostfixExpression p when p.operand == target => p.writeElement,
      _ => null,
    };

/// The instance field [expression] names through `this` inside a method (`this.count`, also as an assignment
/// target), or null.
FieldElement? thisFieldOf(Expression expression) {
  if (expression case PropertyAccess(target: ThisExpression(), :final propertyName)) {
    final field = _fieldOf(propertyName.element) ?? _fieldOf(_writeElementOf(expression));
    return field != null && !field.isStatic && isUserClass(field.enclosingElement) ? field : null;
  }
  return null;
}

/// The unnamed generative constructor of [declaration], or null if it has none (Dart's default constructor).
ConstructorDeclaration? constructorOf(ClassDeclaration declaration) => declaration.body.members
    .whereType<ConstructorDeclaration>()
    .where((c) => c.name == null && c.factoryKeyword == null)
    .firstOrNull;

/// The instance fields of [declaration], in declaration order.
Iterable<VariableDeclaration> instanceFields(ClassDeclaration declaration) =>
    declaration.body.members.whereType<FieldDeclaration>().where((f) => !f.isStatic).expand((f) => f.fields.variables);

/// The expressions compiled from a class body: field initializers, the initializer list's values, and the
/// constructor's default values. Each is a root expression (docs: every expression rule checks it).
Iterable<Expression> classRoots(ClassDeclaration declaration) sync* {
  for (final member in declaration.body.members) {
    switch (member) {
      case FieldDeclaration(:final fields):
        for (final variable in fields.variables) {
          if (variable.initializer case final initializer?) yield initializer;
        }
      case ConstructorDeclaration(:final parameters, :final initializers):
        for (final parameter in parameters.parameters) {
          if (parameter.defaultClause case final clause?) yield clause.value;
        }
        for (final initializer in initializers) {
          if (initializer is ConstructorFieldInitializer) yield initializer.expression;
        }
      default:
    }
  }
}

/// [classRoots] of every user class whose body is compiled: not of a class that extends another (E027 reports it as
/// a whole).
Iterable<Expression> allClassRoots(CompilationUnit unit) =>
    userClassDeclarations(unit).where((c) => c.extendsClause == null).expand(classRoots);

/// Whether [expression] is the initializer of a field of a user class (`final count = Signal(0);` inside a class):
/// the field itself is reported (ClassRule), not its initializer as well.
bool isFieldInitializer(Expression expression) {
  final variable = expression.parent;
  return variable is VariableDeclaration &&
      variable.initializer == expression &&
      variable.parent?.parent is FieldDeclaration &&
      enclosingUserClass(variable) != null;
}

/// The user class whose body contains [node], or null.
ClassDeclaration? enclosingUserClass(AstNode node) {
  final cls = node.thisOrAncestorOfType<ClassDeclaration>();
  return cls != null && isUserClass(cls.declaredFragment?.element) ? cls : null;
}

/// The parameter element [identifier] names if it is a parameter of a user class's constructor, else null.
FormalParameterElement? constructorParameterOf(SimpleIdentifier identifier) {
  final element = identifier.element;
  if (element is! FormalParameterElement) return null;
  return element.enclosingElement is ConstructorElement && isUserClass(element.enclosingElement?.enclosingElement)
      ? element
      : null;
}
