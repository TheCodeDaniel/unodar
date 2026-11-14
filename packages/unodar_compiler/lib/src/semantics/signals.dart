import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';

/// Signals (docs/SUBSET.md "Signals"), matched by resolved element (declared in `package:unodar`), never by
/// spelling. Validator rules and the lowering use these helpers, so "what is a signal, and what is a read or a write
/// of one" is defined once.

/// The signal classes of `package:unodar`: `ReadonlySignal` and its subclasses (`Signal`).
bool isSignalClass(Element? element) =>
    element is ClassElement &&
    isUnodarElement(element) &&
    (element.name == 'ReadonlySignal' ||
        element.allSupertypes.any((t) => t.element.name == 'ReadonlySignal' && isUnodarElement(t.element)));

/// Whether [type] is a signal type (`Signal<int>`, `ReadonlySignal<bool>`).
bool isSignalType(DartType? type) => type is InterfaceType && isSignalClass(type.element);

/// The value type `T` of a signal type, or null if [type] is not one.
DartType? signalValueType(DartType? type) {
  if (type is! InterfaceType || !isSignalClass(type.element)) return null;
  return type.typeArguments.singleOrNull;
}

/// A `Signal(…)` constructor call, or null.
InstanceCreationExpression? signalCreation(Expression? expression) =>
    expression is InstanceCreationExpression && isSignalType(expression.staticType) ? expression : null;

/// The initial value of a `Signal(…)` call.
Expression signalInitialValue(InstanceCreationExpression creation) =>
    creation.argumentList.arguments.single.argumentExpression;

/// A top-level signal: `final count = Signal<int>(0);`. Null if [variable] is not one (E024 decides about the rest).
InstanceCreationExpression? topLevelSignal(VariableDeclaration variable) {
  final list = variable.parent;
  if (list is! VariableDeclarationList || !list.isFinal || list.isConst || list.isLate) return null;
  if (list.parent is! TopLevelVariableDeclaration) return null;
  return signalCreation(variable.initializer);
}

/// `count.value`: the signal name if [expression] reads or writes a signal's value through a plain name, else null.
/// The analyzer gives a `PrefixedIdentifier` for most reads and writes, and a `PropertyAccess` with a plain-name
/// target for some read-write targets (`count.value++`). Other spellings (`(count).value`) stay property accesses
/// (E002).
SimpleIdentifier? signalOfValue(Expression? expression) => switch (expression) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier.name == 'value' && isSignalType(_typeOfName(prefix)) =>
        prefix,
      PropertyAccess(target: final SimpleIdentifier target, :final propertyName)
          when propertyName.name == 'value' && isSignalType(_typeOfName(target)) =>
        target,
      _ => null,
    };

/// The value type `T` of the signal [name] refers to (`count` in `count.value++`), or null.
DartType? signalValueTypeOfName(SimpleIdentifier name) => signalValueType(_typeOfName(name));

/// The type of the variable [name] refers to, from its element when the analyzer leaves `staticType` unset on a
/// read-write target.
DartType? _typeOfName(SimpleIdentifier name) =>
    name.staticType ??
    switch (name.element) {
      GetterElement(:final variable) => variable.type,
      VariableElement(:final type) => type,
      _ => null,
    };

/// Whether [argument] of a widget constructor is a signal argument: its parameter has a signal type (`Watch`'s
/// signal, and from step 9 `Led`'s `on:`). Signal arguments are references, not C++ constructor arguments or
/// constants; E024 requires the name of a top-level signal.
bool isSignalArgument(Argument argument) => isSignalType(argument.correspondingParameter?.type);

/// The argument [expression] is, if it is one (`count` in `Watch(count, …)` or `Led(on: count)`), else null.
Argument? argumentOf(Expression expression) => switch (expression.parent) {
      NamedArgument() && final named => named,
      ArgumentList() => expression as Argument,
      _ => null,
    };
