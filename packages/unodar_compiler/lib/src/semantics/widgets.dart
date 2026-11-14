import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import 'constant_evaluator.dart';
import 'elements.dart';
import 'signals.dart';

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

/// The widget constructor call that [closure] is an argument of, or null. Such a closure is a widget callback
/// (`onPressed: () { … }`); any other closure is E012.
InstanceCreationExpression? widgetOfCallback(FunctionExpression closure) {
  var list = closure.parent;
  if (list is NamedArgument) list = list.parent;
  final creation = list is ArgumentList ? list.parent : null;
  return creation is InstanceCreationExpression ? widgetCreation(creation) : null;
}

/// Whether [argument] of a widget constructor is a callback: its parameter has a function type (`onPressed`,
/// `Every`'s callback). Callbacks are not C++ constructor arguments.
bool isCallbackArgument(Argument argument) => argument.correspondingParameter?.type is FunctionType;

/// The arguments of a widget constructor that are passed to C++ (all but the callbacks and the signal arguments),
/// in source order.
List<Argument> cppArgumentsOf(InstanceCreationExpression creation) => [
      for (final argument in creation.argumentList.arguments)
        if (isCppConstructorArgument(argument)) argument,
    ];

/// Whether [argument] of a widget constructor is passed to its C++ constructor: neither a callback nor a signal.
bool isCppConstructorArgument(Argument argument) => !isCallbackArgument(argument) && !isSignalArgument(argument);

/// The callback closure of a widget constructor, or null.
FunctionExpression? callbackOf(InstanceCreationExpression creation) => [
      for (final argument in creation.argumentList.arguments)
        if (isCallbackArgument(argument) && argument.argumentExpression is FunctionExpression)
          argument.argumentExpression as FunctionExpression,
    ].firstOrNull;

/// The name of the callback parameter [closure] is passed to (`onPressed`, `callback`).
String callbackParameterName(FunctionExpression closure) {
  final argument = closure.parent is NamedArgument ? closure.parent! as Argument : closure as Argument;
  return argument.correspondingParameter?.name ?? 'callback';
}

/// The C++ function a callback becomes: `unodar_button_onPressed` for a top-level `button`,
/// `unodar_every_0_callback` for the first `Every` written in `children`.
String callbackFunctionName(String objectName, FunctionExpression closure) {
  final prefix = objectName.startsWith('unodar_') ? objectName : 'unodar_$objectName';
  return '${prefix}_${callbackParameterName(closure)}';
}

/// The widgets of a widget program whose declaration is accepted (a top-level `final`, or written in
/// `Device.children`), with their C++ object names, in source order. Empty for any other program.
List<(String, InstanceCreationExpression)> acceptedWidgets(CompilationUnit unit) {
  final device = deviceOf(unit);
  if (device == null) return const [];
  final inline = {for (final child in widgetChildren(device, unit)) child.creation: child.name};
  return [
    for (final variable in topLevelVariables(unit))
      if (topLevelWidget(variable) case final creation?) (variable.name.lexeme, creation),
    for (final creation in inlineWidgets(unit)) (inline[creation]!, creation),
  ]..sort((a, b) => a.$2.offset.compareTo(b.$2.offset));
}

/// The callback closures of the accepted widgets, in source order. Their bodies are compiled like function bodies.
List<FunctionExpression> widgetCallbacks(CompilationUnit unit) => [
      for (final (_, creation) in acceptedWidgets(unit))
        if (callbackOf(creation) case final callback?) callback,
    ];

/// Whether [expression] is a `Duration(…)` constructor call (`dart:core`, unnamed constructor, `const` or not).
bool isDurationCreation(Expression expression) =>
    expression is InstanceCreationExpression &&
    expression.constructorName.name == null &&
    isDurationType(expression.staticType);

/// Whether [type] is `dart:core`'s `Duration`.
bool isDurationType(DartType? type) =>
    type is InterfaceType && type.element.name == 'Duration' && type.element.library.isDartCore;

/// Whether [expression] is a `Duration(…)` written as an argument of a widget constructor (`Every`'s interval).
bool isWidgetInterval(Expression expression) {
  if (!isDurationCreation(expression)) return false;
  final list = expression.parent;
  final creation = list is ArgumentList ? list.parent : null;
  return creation is InstanceCreationExpression && widgetCreation(creation) != null;
}

/// The interval of a `Duration(…)` in milliseconds, or why it is not a valid widget interval.
sealed class Interval {
  const Interval();
}

final class IntervalMilliseconds extends Interval {
  const IntervalMilliseconds(this.milliseconds);

  final int milliseconds;
}

/// An argument that is not a compile-time constant.
final class IntervalNotConstant extends Interval {
  const IntervalNotConstant(this.argument);

  final Expression argument;
}

/// Constant, but not a whole number of milliseconds from 1 to 2147483647. [microseconds] is the exact total.
final class IntervalOutOfRange extends Interval {
  const IntervalOutOfRange(this.microseconds);

  final int microseconds;
}

/// The largest interval, in milliseconds: `Every` compares `uint32_t` times, and the value is a Dart `int`
/// (int32_t) constant.
const maxIntervalMilliseconds = 2147483647;

/// Evaluates `Duration(days:, hours:, minutes:, seconds:, milliseconds:, microseconds:)` with Dart semantics.
Interval intervalOf(InstanceCreationExpression duration, ConstantEvaluator constants) {
  const microsecondsPer = {
    'days': 86400000000,
    'hours': 3600000000,
    'minutes': 60000000,
    'seconds': 1000000,
    'milliseconds': 1000,
    'microseconds': 1,
  };
  var total = 0;
  for (final argument in duration.argumentList.arguments.whereType<NamedArgument>()) {
    final value = constants.valueOf(argument.argumentExpression);
    if (value is! int) return IntervalNotConstant(argument.argumentExpression);
    total += value * microsecondsPer[argument.name.lexeme]!;
  }
  if (total % 1000 != 0 || total < 1000 || total > maxIntervalMilliseconds * 1000) return IntervalOutOfRange(total);
  return IntervalMilliseconds(total ~/ 1000);
}
