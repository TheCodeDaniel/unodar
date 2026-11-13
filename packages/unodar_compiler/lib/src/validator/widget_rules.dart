import 'package:analyzer/dart/ast/ast.dart';

import '../diagnostics/diagnostics.dart';
import '../semantics/constant_evaluator.dart';
import '../semantics/elements.dart';
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
    for (final argument in creation.argumentList.arguments) {
      final value = argument.argumentExpression;
      // Unsupported expressions are reported by ExpressionRule (E002/E012) instead.
      if (subexpressions(value).any((e) => expressionIssue(e) != null)) continue;
      if (context.constants.evaluate(value) is! NotConstant) continue;
      final parameter = argument is NamedArgument ? argument.name.lexeme : 'argument';
      context.report(Diagnostics.widgetArgumentNotConstant('the $parameter of $widget', context.at(argument)));
    }
  }
}

/// Every widget constructor call in a compiled position (top-level initializers, `Device.children`, function
/// bodies), in source order.
Iterable<InstanceCreationExpression> widgetCreations(CompilationUnit unit) => allRootExpressions(unit)
    .expand(subexpressions)
    .whereType<InstanceCreationExpression>()
    .where((c) => widgetCreation(c) != null);
