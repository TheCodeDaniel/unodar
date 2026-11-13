import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../diagnostics/diagnostics.dart';
import '../semantics/constant_evaluator.dart';
import '../semantics/elements.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import '../semantics/widgets.dart';
import 'rules.dart';

/// `main()` is exactly one `runDevice(Device(…))` call (E008); a widget program has no `setup()`/`loop()` (E021).
///
/// A `main()` of another shape is reported alone: the file is then neither a widget program nor a plain sketch,
/// and reporting its `setup()`/`loop()` or its widgets as well would only add noise.
final class MainRule implements ValidationRule {
  const MainRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final main = mainFunction(unit);
    if (main == null) return;
    if (deviceOfMain(main) == null) {
      context.report(Diagnostics.unsupportedMain(context.at(main.name)));
      return;
    }
    for (final function in compiledFunctions(unit).where(isEntryPoint)) {
      context.report(Diagnostics.widgetProgramEntryPoint(function.name.lexeme, context.at(function.name)));
    }
  }
}

/// The shape of a widget program (E021): widgets only in a widget program; `Device(board: Uno(), children: [...])`
/// with a list literal of widgets. (`runDevice`, `Device` and `Uno` outside `main()` are E021 from
/// [ExpressionRule], in any program.)
final class WidgetProgramRule implements ValidationRule {
  const WidgetProgramRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final device = deviceOf(unit);
    if (device == null) {
      if (mainFunction(unit) != null) return; // E008.
      for (final creation in widgetCreations(unit)) {
        final name = widgetClassOf(creation.staticType)!.name;
        context.report(Diagnostics.widgetOutsideWidgetProgram("the widget '$name'", context.at(creation)));
      }
      return;
    }

    for (final call in allCalls(unit).where(isSerialBegin)) {
      context.report(Diagnostics.serialBeginInWidgetProgram(context.at(call)));
    }
    if (namedArgument(device, 'serialBaud') case final baud?
        when !subexpressions(baud).any((e) => expressionIssue(e) != null)) {
      final value = context.constants.valueOf(baud);
      if (context.constants.evaluate(baud) is NotConstant) {
        context.report(Diagnostics.serialBaudNotConstant(context.at(baud)));
      } else if (value is int && value < 0) {
        // Serial.begin's `unsigned long baud`, as for an explicit Serial.begin (E004).
        context.report(Diagnostics.argumentOutOfRange(
            '$value', 'serialBaud', 'Device', 'unsigned long', '0 to 4294967295', context.at(baud)));
      }
    }

    final board = namedArgument(device, 'board');
    if (board != null && !(board is InstanceCreationExpression && isUnodarClass(board.staticType, 'Uno'))) {
      context.report(Diagnostics.deviceBoard(context.at(board)));
    }

    final elements = childrenElements(device);
    if (elements == null) {
      final children = namedArgument(device, 'children');
      if (children != null) context.report(Diagnostics.deviceChildrenNotLiteral(context.at(children)));
      return;
    }
    for (final element in elements) {
      final problem = switch (element) {
        SpreadElement() => 'a spread (`...`)',
        IfElement() => 'a collection `if`',
        ForElement() => 'a collection `for`',
        Expression() when widgetCreation(element) != null => null,
        SimpleIdentifier() when _isTopLevelWidget(element, unit) => null,
        _ => "'${element.toSource()}'",
      };
      if (problem != null) context.report(Diagnostics.deviceChildElement(problem, context.at(element)));
    }
  }

  /// Whether [identifier] names a top-level variable initialized by a widget constructor (if that declaration
  /// breaks a rule, E022 reports it there).
  static bool _isTopLevelWidget(SimpleIdentifier identifier, CompilationUnit unit) =>
      widgetCreation(topLevelDeclarationOf(identifier, unit)?.initializer) != null;
}

/// Widget rules (E022) in a widget program: placement (a top-level `final`, or written in `Device.children`) and
/// compile-time-constant arguments.
final class WidgetRule implements ValidationRule {
  const WidgetRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    if (deviceOf(unit) == null) return; // A sketch (E021) or an unsupported main() (E008).
    final inline = inlineWidgets(unit).toSet();
    final topLevel = {
      for (final variable in topLevelVariables(unit))
        if (widgetCreation(variable.initializer) case final creation?) creation: variable,
    };
    for (final creation in widgetCreations(unit)) {
      final name = widgetClassOf(creation.staticType)!.name!;
      if (topLevel[creation] case final variable?) {
        if (topLevelWidget(variable) == null) {
          final example = 'final ${variable.name.lexeme} = ${creation.toSource()};';
          context.report(Diagnostics.widgetNotFinal(variable.name.lexeme, example, context.at(variable.name)));
          continue;
        }
      } else if (!inline.contains(creation)) {
        context.report(Diagnostics.widgetPlacement(name, context.at(creation)));
        continue;
      }
      _constantArguments(creation, name, context);
    }
  }

  void _constantArguments(InstanceCreationExpression creation, String widget, ValidationContext context) {
    for (final argument in cppArgumentsOf(creation)) {
      final value = argument.argumentExpression;
      if (isDurationType(value.staticType)) {
        _interval(value, context);
        continue;
      }
      // Unsupported expressions are reported by ExpressionRule (E002/E012) instead.
      if (subexpressions(value).any((e) => expressionIssue(e) != null)) continue;
      if (context.constants.evaluate(value) is! NotConstant) continue;
      final parameter = argument is NamedArgument ? argument.name.lexeme : 'argument';
      context.report(Diagnostics.widgetArgumentNotConstant('the $parameter of $widget', context.at(argument)));
    }
  }
}

void _interval(Expression value, ValidationContext context) {
  if (subexpressions(value).any((e) => expressionIssue(e) != null)) return; // E002 (e.g. `Duration.zero`).
  if (!isDurationCreation(value)) {
    context.report(Diagnostics.intervalNotDuration(context.at(value)));
    return;
  }
  // Constant arguments that do not fit int32 are E010 already.
  final arguments = (value as InstanceCreationExpression).argumentList.arguments;
  if (arguments.any((a) => context.constants.evaluate(a.argumentExpression) is ConstantProblem)) return;
  switch (intervalOf(value, context.constants)) {
    case IntervalNotConstant(:final argument):
      context.report(Diagnostics.intervalNotConstant(context.at(argument)));
    case IntervalOutOfRange(:final microseconds):
      context.report(Diagnostics.intervalOutOfRange(microseconds, context.at(value)));
    case IntervalMilliseconds():
  }
}

/// Every widget constructor call in a compiled position (top-level initializers, `Device.children`, function
/// bodies), in source order.
Iterable<InstanceCreationExpression> widgetCreations(CompilationUnit unit) => allRootExpressions(unit)
    .expand(subexpressions)
    .whereType<InstanceCreationExpression>()
    .where((c) => widgetCreation(c) != null);

/// A widget callback is a closure without parameters that is not async or a generator (E012). Its body is checked
/// like a function body by the other rules.
final class CallbackRule implements ValidationRule {
  const CallbackRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final callback in widgetCallbacks(unit)) {
      final body = callback.body;
      final problems = [
        if (callback.parameters?.parameters.isNotEmpty ?? false) 'it takes parameters',
        if (callback.typeParameters != null) 'it has type parameters',
        if (body.isAsynchronous) 'it is async',
        if (body.isGenerator) 'it is a generator',
      ];
      if (problems.isNotEmpty) {
        context.report(Diagnostics.callbackShape(englishList(problems), context.at(callback)));
      }
    }
  }
}

/// Each pin belongs to one widget (E022). Widgets are compared in source order; the later one is reported.
final class WidgetPinRule implements ValidationRule {
  const WidgetPinRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final owners = <int, String>{};
    for (final (name, creation) in acceptedWidgets(unit)) {
      final pin = namedArgument(creation, 'pin');
      final value = pin == null ? null : context.constants.valueOf(pin);
      if (value is! int) continue;
      final line = context.at(creation).line;
      final owner = name.startsWith('unodar_')
          ? 'the ${widgetClassOf(creation.staticType)!.name} on line $line'
          : "'$name' (line $line)";
      final previous = owners[value];
      if (previous != null) {
        context.report(
            Diagnostics.duplicatePin(value, previous, context.at(pin!.parent is NamedArgument ? pin.parent! : pin)));
      } else {
        owners[value] = owner;
      }
    }
  }
}

/// Every top-level widget is listed in `Device.children` exactly once (E022).
final class WidgetChildrenRule implements ValidationRule {
  const WidgetChildrenRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final device = deviceOf(unit);
    if (device == null) return;
    final listed = <VariableDeclaration>{};
    for (final element in childrenElements(device) ?? const <CollectionElement>[]) {
      if (element is! SimpleIdentifier) continue;
      final variable = topLevelDeclarationOf(element, unit);
      if (variable == null || topLevelWidget(variable) == null) continue;
      if (!listed.add(variable)) context.report(Diagnostics.widgetListedTwice(element.name, context.at(element)));
    }
    if (childrenElements(device) == null) return; // E021: the list is not readable.
    for (final variable in topLevelVariables(unit)) {
      if (topLevelWidget(variable) != null && !listed.contains(variable)) {
        context.report(Diagnostics.widgetNotInChildren(variable.name.lexeme, context.at(variable.name)));
      }
    }
  }
}

/// A top-level widget's callback may only use top-level widgets declared above it (E022), like the order rule for
/// top-level initializers (E015). Widgets written in `children` may use every widget.
final class WidgetOrderRule implements ValidationRule {
  const WidgetOrderRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    if (deviceOf(unit) == null) return;
    final widgets = [
      for (final variable in topLevelVariables(unit))
        if (topLevelWidget(variable) != null) variable,
    ];
    final index = {for (final (i, v) in widgets.indexed) v.declaredFragment!.element: i};
    for (final (i, variable) in widgets.indexed) {
      final callback = callbackOf(topLevelWidget(variable)!);
      if (callback == null) continue;
      final reported = <Object>{};
      callback.body.accept(_IdentifierVisitor((identifier) {
        final reference = referenceOf(identifier);
        if (reference is! GlobalReference) return;
        final used = index[reference.element];
        if (used != null && used > i && reported.add(reference.element)) {
          context.report(
              Diagnostics.widgetUsedBeforeDeclaration(variable.name.lexeme, identifier.name, context.at(identifier)));
        }
      }));
    }
  }
}

final class _IdentifierVisitor extends RecursiveAstVisitor<void> {
  _IdentifierVisitor(this.onIdentifier);

  final void Function(SimpleIdentifier identifier) onIdentifier;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) => onIdentifier(node);
}

/// A widget handle is only the receiver of a method call or an entry of `children` (E022); widget types appear
/// nowhere else (parameters, locals, return values).
final class WidgetHandleRule implements ValidationRule {
  const WidgetHandleRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final root in allRootExpressions(unit)) {
      walkExpression(root, (expression) {
        if (expression is SimpleIdentifier && widgetClassOf(expression.staticType) != null) {
          if (referenceOf(expression) is GlobalReference) {
            context.report(Diagnostics.widgetHandleUse(expression.name, context.at(expression)));
          }
          return false;
        }
        return expressionIssue(expression) == null;
      });
    }
    for (final function in compiledFunctions(unit)) {
      if (function.returnType case final type? when widgetClassOf(type.type) != null) {
        context.report(Diagnostics.widgetTypePosition('a return value', type.toSource(), context.at(type)));
      }
      for (final parameter in function.functionExpression.parameters?.parameters ?? const <FormalParameter>[]) {
        final type = parameter.declaredFragment?.element.type;
        if (widgetClassOf(type) == null) continue;
        context.report(Diagnostics.widgetTypePosition('a parameter', displayType(type!), context.at(parameter)));
      }
    }
    for (final body in compiledBodies(unit)) {
      for (final statement in statementsIn(body)) {
        final list = switch (statement) {
          VariableDeclarationStatement(:final variables) => variables,
          ForStatement(forLoopParts: ForPartsWithDeclarations(:final variables)) => variables,
          _ => null,
        };
        for (final variable in list?.variables ?? const <VariableDeclaration>[]) {
          final type = variable.declaredFragment?.element.type;
          // A widget constructor in a local is reported once, as a misplaced widget.
          if (widgetClassOf(type) == null || widgetCreation(variable.initializer) != null) continue;
          context.report(Diagnostics.widgetTypePosition(
              'a local variable', displayType(type!), context.at(list!.type ?? variable.name)));
        }
      }
    }
  }
}
