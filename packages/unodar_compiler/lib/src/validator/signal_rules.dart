import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import '../diagnostics/diagnostics.dart';
import '../semantics/elements.dart';
import '../semantics/signals.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import '../semantics/widgets.dart';
import 'rules.dart';

/// Signals (docs/SUBSET.md "Signals"):
/// * only in a widget program (E021);
/// * created only as the initializer of a top-level `final` (E024);
/// * used only through `.value`: not stored, compared, passed, printed, or returned, and no local, parameter, or
///   return value has a signal type (E024);
/// * with a supported value type `T` (E009).
///
/// Uses of a declaration that was already rejected are not reported again.
final class SignalRule implements ValidationRule {
  const SignalRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final creations = [for (final root in allRootExpressions(unit)) ...subexpressions(root).where(_isCreation)]
        .cast<InstanceCreationExpression>();
    if (deviceOf(unit) == null) {
      if (mainFunction(unit) != null) return; // E008.
      for (final creation in creations) {
        context.report(Diagnostics.widgetOutsideWidgetProgram('a signal', context.at(creation)));
      }
      return;
    }

    // Declarations and creations.
    final rejected = <Element>{};
    final accepted = <InstanceCreationExpression>{};
    for (final variable in topLevelVariables(unit)) {
      final creation = signalCreation(variable.initializer);
      if (creation == null) continue;
      if (topLevelSignal(variable) != null) {
        accepted.add(creation);
      } else if (!(variable.parent as VariableDeclarationList).isLate) {
        // `var`, or no keyword: must be final. (`late` is E005, `const` an analyzer error.)
        final name = variable.name.lexeme;
        context.report(
            Diagnostics.signalNotFinal(name, 'final $name = ${creation.toSource()};', context.at(variable.name)));
        accepted.add(creation); // Its initial value and type are still checked.
        if (variable.declaredFragment?.element case final element?) rejected.add(element);
      }
    }
    for (final creation in creations) {
      if (!accepted.contains(creation)) {
        context.report(Diagnostics.signalCreationPosition(_example(creation), context.at(creation)));
      }
      _checkValueType(creation, context);
    }

    // Values: a signal anywhere but before `.value` or as a widget's signal argument (`Watch(count, …)`), which
    // must be the name of a top-level signal.
    final signals = {
      for (final variable in topLevelVariables(unit))
        if (topLevelSignal(variable) != null)
          if (variable.declaredFragment?.element case final element?) element,
    };
    Element? globalOf(Expression expression) => switch (expression) {
          SimpleIdentifier() => switch (referenceOf(expression)) {
              GlobalReference(:final element) => element,
              _ => null,
            },
          _ => null,
        };
    for (final root in allRootExpressions(unit)) {
      walkExpression(root, (expression) {
        if (!isSignalType(expression.staticType) || signalCreation(expression) != null) {
          return expressionIssue(expression) == null;
        }
        final element = globalOf(expression);
        if (rejected.contains(element)) return false; // Reported at its declaration.
        final argument = argumentOf(expression);
        if (argument != null && isSignalArgument(argument)) {
          if (!signals.contains(element)) {
            final creation = argument.parent!.parent! as InstanceCreationExpression;
            context.report(Diagnostics.signalArgument(argument.correspondingParameter!.name!,
                widgetClassOf(creation.staticType)?.name ?? 'the widget', context.at(expression)));
          }
          return false;
        }
        if (element != null || expression is! SimpleIdentifier) {
          final name = expression is SimpleIdentifier ? expression.name : expression.toSource();
          context.report(Diagnostics.signalUse(name, context.at(expression)));
        }
        return false;
      });
    }

    // Types: parameters, return values, locals.
    for (final function in compiledFunctions(unit)) {
      if (function.returnType case final type? when isSignalType(type.type)) {
        context.report(Diagnostics.signalTypePosition('a return value', type.toSource(), context.at(type)));
      }
      for (final parameter in function.functionExpression.parameters?.parameters ?? const <FormalParameter>[]) {
        final type = parameter.declaredFragment?.element.type;
        if (!isSignalType(type)) continue;
        context.report(Diagnostics.signalTypePosition('a parameter', displayType(type!), context.at(parameter)));
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
          // A signal created in a local is reported once, as a misplaced creation.
          if (!isSignalType(type) || signalCreation(variable.initializer) != null) continue;
          context.report(Diagnostics.signalTypePosition(
              'a local variable', displayType(type!), context.at(list!.type ?? variable.name)));
        }
      }
    }
  }

  static bool _isCreation(Expression expression) => signalCreation(expression) != null;

  /// `final local = Signal(1);` for a creation in a local's initializer, else `final value = Signal(…);`.
  static String _example(InstanceCreationExpression creation) {
    final parent = creation.parent;
    final name = parent is VariableDeclaration && parent.initializer == creation ? parent.name.lexeme : 'value';
    return 'final $name = ${creation.toSource()};';
  }

  /// `Signal<num>(1)`: `T` must be supported. An unsupported initial value is reported by the expression type rule
  /// instead (`Signal(true ? 1 : 2.5)`, type `num`), so each problem is reported once.
  static void _checkValueType(InstanceCreationExpression creation, ValidationContext context) {
    final valueType = signalValueType(creation.staticType);
    if (valueType == null || irTypeOf(valueType) != null) return;
    if (irTypeOf(signalInitialValue(creation).staticType) == null) return;
    final explicit = creation.constructorName.type.typeArguments?.arguments.singleOrNull;
    final declared = switch (creation.parent) {
      VariableDeclaration(parent: VariableDeclarationList(:final type?)) => type,
      _ => null,
    };
    context.report(typeDiagnostic(valueType, context.at(explicit ?? declared ?? creation)));
  }
}
