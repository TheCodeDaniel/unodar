import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import 'types.dart';

/// The user's enums (docs/SUBSET.md "Enums"), shared by the validator and the lowering.

/// The user's enum declarations, in source order.
Iterable<EnumDeclaration> userEnumDeclarations(CompilationUnit unit) => unit.declarations.whereType<EnumDeclaration>();

/// Whether [declaration] is a simple enum: values without arguments, no members, no `implements`/`with`, no type
/// parameters (E028 otherwise).
bool isSimpleEnum(EnumDeclaration declaration) =>
    declaration.body.members.isEmpty &&
    declaration.implementsClause == null &&
    declaration.withClause == null &&
    declaration.namePart.typeParameters == null &&
    declaration.body.constants.every((c) => c.arguments == null);

/// The enum value [expression] names (`Mode.idle`), or null.
FieldElement? enumValueOf(Expression expression) {
  if (expression case PrefixedIdentifier(:final prefix, :final identifier)
      when prefix.element is EnumElement && userEnumOf((prefix.element as EnumElement).thisType) != null) {
    final element = identifier.element;
    final field = element is GetterElement ? element.variable : element;
    return field is FieldElement && field.isEnumConstant ? field : null;
  }
  return null;
}

/// The enum value whose `.index` [expression] reads (`mode.index`, `left.mode.index`), or null.
Expression? enumIndexTarget(Expression expression) {
  final (Expression? target, SimpleIdentifier? property) = switch (expression) {
    PrefixedIdentifier(:final prefix, :final identifier) => (prefix, identifier),
    PropertyAccess(:final target?, :final propertyName) => (target, propertyName),
    _ => (null, null),
  };
  if (target == null || property?.name != 'index' || userEnumOf(target.staticType) == null) return null;
  return target;
}

/// `Mode.values` or `mode.name` (E028): the member's name, or null.
String? unsupportedEnumMember(Expression expression) {
  final (Expression? target, SimpleIdentifier? property) = switch (expression) {
    PrefixedIdentifier(:final prefix, :final identifier) => (prefix, identifier),
    PropertyAccess(:final target?, :final propertyName) => (target, propertyName),
    _ => (null, null),
  };
  if (target == null || property == null) return null;
  final isEnumType = target is SimpleIdentifier && target.element is EnumElement;
  if (isEnumType && property.name == 'values') return 'values';
  if (!isEnumType && userEnumOf(target.staticType) != null && property.name != 'index') return property.name;
  return null;
}
