import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import 'elements.dart';

/// The static widget tree (docs/SUBSET.md "Widgets: runDevice"), read from `main()` without running it.
///
/// Validator rules and the lowering use these helpers, so "what is a widget program, which widgets does it have,
/// and what are they called in C++" is defined once. Matching is by resolved element (declared in `package:unodar`),
/// never by spelling.

/// Whether [element] is a widget class from `package:unodar` (`Led`, `Button`, `Every`): a subclass of its `Widget`.
bool isWidgetClass(Element? element) =>
    element is ClassElement &&
    isUnodarElement(element) &&
    element.allSupertypes.any((t) => t.element.name == 'Widget' && isUnodarElement(t.element));

/// The widget class [type] names, or null.
ClassElement? widgetClassOf(DartType? type) =>
    type is InterfaceType && isWidgetClass(type.element) ? type.element as ClassElement : null;

/// Whether [type] is `package:unodar`'s class [name] (`Device`, `Uno`).
bool isUnodarClass(DartType? type, String name) =>
    type is InterfaceType && type.element.name == name && isUnodarElement(type.element);

/// Whether [call] is `package:unodar`'s `runDevice(…)`.
bool isRunDeviceCall(MethodInvocation call) {
  final element = call.methodName.element;
  return call.target == null &&
      element is TopLevelFunctionElement &&
      isUnodarElement(element) &&
      element.name == 'runDevice';
}

/// A constructor call of a widget class, or null.
InstanceCreationExpression? widgetCreation(Expression? expression) =>
    expression is InstanceCreationExpression && widgetClassOf(expression.staticType) != null ? expression : null;

/// The top-level `main()` declaration, or null.
FunctionDeclaration? mainFunction(CompilationUnit unit) => unit.declarations
    .whereType<FunctionDeclaration>()
    .where((f) => f.name.lexeme == 'main' && !f.isGetter && !f.isSetter)
    .firstOrNull;

/// The `Device(…)` that [main] passes to `runDevice`, if [main] has exactly the supported shape (E008 otherwise):
/// `void main() => runDevice(Device(…));` or `void main() { runDevice(Device(…)); }`.
InstanceCreationExpression? deviceOfMain(FunctionDeclaration main) {
  final function = main.functionExpression;
  final body = function.body;
  if (main.returnType?.toSource() != 'void' || function.typeParameters != null) return null;
  if (function.parameters?.parameters.isNotEmpty ?? true) return null;
  if (body.isAsynchronous || body.isGenerator) return null;
  final call = switch (body) {
    ExpressionFunctionBody(:final expression) => expression,
    BlockFunctionBody(block: Block(statements: [ExpressionStatement(:final expression)])) => expression,
    _ => null,
  };
  if (call is! MethodInvocation || !isRunDeviceCall(call)) return null;
  final argument = call.argumentList.arguments.singleOrNull;
  if (argument is! InstanceCreationExpression || !isUnodarClass(argument.staticType, 'Device')) return null;
  return argument;
}

/// The `Device(…)` of a widget program, or null if [unit] has no `main()` of the supported shape.
InstanceCreationExpression? deviceOf(CompilationUnit unit) {
  final main = mainFunction(unit);
  return main == null ? null : deviceOfMain(main);
}

/// The named argument [name] of a constructor call, or null.
Expression? namedArgument(InstanceCreationExpression creation, String name) => creation.argumentList.arguments
    .whereType<NamedArgument>()
    .where((a) => a.name.lexeme == name)
    .firstOrNull
    ?.argumentExpression;

/// The elements of `children: [...]` if it is a list literal; null otherwise (E021).
List<CollectionElement>? childrenElements(InstanceCreationExpression device) =>
    switch (namedArgument(device, 'children')) {
      ListLiteral(:final elements) => elements,
      _ => null,
    };

/// The widget constructors written directly in the children of the widget program in [unit], in list order.
List<InstanceCreationExpression> inlineWidgets(CompilationUnit unit) {
  final device = deviceOf(unit);
  if (device == null) return const [];
  return [
    for (final element in childrenElements(device) ?? const <CollectionElement>[])
      if (element is Expression && widgetCreation(element) != null) element as InstanceCreationExpression,
  ];
}

/// The parts of a widget program's `main()` that are compiled, as root expressions: the widgets written in
/// `children`, then the `serialBaud:` value.
Iterable<Expression> deviceRoots(CompilationUnit unit) sync* {
  yield* inlineWidgets(unit);
  final device = deviceOf(unit);
  if (device != null) {
    if (namedArgument(device, 'serialBaud') case final baud?) yield baud;
  }
}

/// The default of `Device`'s `serialBaud` parameter, from its Dart declaration (the single source of truth).
int serialBaudDefault(InstanceCreationExpression device) {
  final parameter = device.constructorName.element?.formalParameters.where((p) => p.name == 'serialBaud').single;
  return parameter?.computeConstantValue()?.toIntValue() ?? (throw StateError('Device has no serialBaud default'));
}

/// Whether [call] is `Serial.begin(…)` (`HardwareSerial.begin` from `package:unodar`).
bool isSerialBegin(MethodInvocation call) {
  final method = call.methodName.element;
  return method is MethodElement &&
      isUnodarElement(method) &&
      method.enclosingElement?.name == 'HardwareSerial' &&
      method.name == 'begin';
}

/// The top-level variable declaration [identifier] refers to in [unit], or null.
VariableDeclaration? topLevelDeclarationOf(SimpleIdentifier identifier, CompilationUnit unit) {
  final reference = referenceOf(identifier);
  if (reference is! GlobalReference) return null;
  for (final variable in topLevelVariables(unit)) {
    if (variable.declaredFragment?.element == reference.element) return variable;
  }
  return null;
}

/// A top-level widget: `final led = Led(pin: 13);`. Null if [variable] is not one (E022 decides about the rest).
InstanceCreationExpression? topLevelWidget(VariableDeclaration variable) {
  final list = variable.parent;
  if (list is! VariableDeclarationList || !list.isFinal || list.isConst || list.isLate) return null;
  return widgetCreation(variable.initializer);
}

/// One widget of the tree, in `children` order: its C++ name and its constructor call.
final class WidgetChild {
  const WidgetChild(this.name, this.creation, this.element);

  /// The C++ object name: the variable name for a top-level widget, `unodar_<kind>_<n>` for one written in
  /// `children` (n counts that kind in list order).
  final String name;
  final InstanceCreationExpression creation;

  /// The list element (an identifier or the constructor call itself), for `#line`.
  final Expression element;

  ClassElement get widgetClass => widgetClassOf(creation.staticType)!;
}

/// The widgets in [device]'s children that are a top-level widget or written in place, in list order. Anything
/// else in the list is skipped here (E021 reports it).
List<WidgetChild> widgetChildren(InstanceCreationExpression device, CompilationUnit unit) {
  final counts = <String, int>{};
  final children = <WidgetChild>[];
  for (final element in childrenElements(device) ?? const <CollectionElement>[]) {
    if (element is InstanceCreationExpression && widgetCreation(element) != null) {
      final kind = widgetClassOf(element.staticType)!.name!.toLowerCase();
      final index = counts[kind] = (counts[kind] ?? -1) + 1;
      children.add(WidgetChild(
        'unodar_${kind}_$index',
        element,
        element,
      ));
    } else if (element is SimpleIdentifier) {
      final variable = topLevelDeclarationOf(element, unit);
      final creation = variable == null ? null : topLevelWidget(variable);
      if (creation != null) children.add(WidgetChild(element.name, creation, element));
    }
  }
  return children;
}
