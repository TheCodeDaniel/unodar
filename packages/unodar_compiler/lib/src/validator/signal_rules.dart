import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
      final creation = signalObjectCreation(variable.initializer);
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
        if (!isSignalType(expression.staticType) || signalObjectCreation(expression) != null) {
          return expressionIssue(expression) == null;
        }
        final element = globalOf(expression);
        if (rejected.contains(element)) return false; // Reported at its declaration.
        final argument = argumentOf(expression);
        if (argument != null && isSignalArgument(argument)) {
          final creation = argument.parent!.parent! as InstanceCreationExpression;
          final widget = widgetClassOf(creation.staticType)?.name ?? 'the widget';
          if (!signals.contains(element)) {
            context.report(
                Diagnostics.signalArgument(argument.correspondingParameter!.name!, widget, context.at(expression)));
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
          if (!isSignalType(type) || signalObjectCreation(variable.initializer) != null) continue;
          context.report(Diagnostics.signalTypePosition(
              'a local variable', displayType(type!), context.at(list!.type ?? variable.name)));
        }
      }
    }
  }

  static bool _isCreation(Expression expression) => signalObjectCreation(expression) != null;

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
    // The value it is computed from: the initial value, or a Computed's expression.
    final value = signalCreation(creation) != null
        ? signalInitialValue(creation)
        : switch (computedClosure(creation)) { final closure? => computedExpression(closure), null => null };
    if (value == null || irTypeOf(value.staticType) == null) return;
    final explicit = creation.constructorName.type.typeArguments?.arguments.singleOrNull;
    final declared = switch (creation.parent) {
      VariableDeclaration(parent: VariableDeclarationList(:final type?)) => type,
      _ => null,
    };
    context.report(typeDiagnostic(valueType, context.at(explicit ?? declared ?? creation)));
  }
}

/// No reactive cycles (E025): a Watch may not write, directly or through the functions it calls, the signal it
/// watches, and Watches may not write each other's signals in a circle. Under once-per-pass delivery such a program
/// would deliver on every pass for ever.
///
/// The graph has an edge from signal S to signal T when a Watch of S writes T; each edge keeps the write found first
/// by a breadth-first search from the first such Watch in source order (so its function path is the shortest). Each
/// strongly connected component with a cycle is reported once: the shortest cycle through its first signal in
/// declaration order, at that cycle's first write in source order, with the path rotated to end at that write.
final class ReactiveCycleRule implements ValidationRule {
  const ReactiveCycleRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final device = deviceOf(unit);
    if (device == null) return;
    final signals = [
      for (final variable in topLevelVariables(unit))
        if (topLevelSignal(variable) != null) variable.name.lexeme,
    ];
    final functions = {for (final f in compiledFunctions(unit)) f.declaredFragment?.element: f};

    // Watches in source order, with the name of the signal they watch.
    final watches = <(String, FunctionExpression)>[];
    for (final (_, creation) in acceptedWidgets(unit)) {
      if (widgetClassOf(creation.staticType)?.name != 'Watch') continue;
      final source = creation.argumentList.arguments.where(isSignalArgument).firstOrNull?.argumentExpression;
      final callback = callbackOf(creation);
      if (source is! SimpleIdentifier || callback == null || !signals.contains(source.name)) continue;
      watches.add((source.name, callback));
    }
    watches.sort((x, y) => x.$2.offset.compareTo(y.$2.offset));

    final edges = <String, Map<String, _Write>>{};
    for (final (source, callback) in watches) {
      final queue = <(FunctionBody, String)>[(callback.body, 'Watch($source)')];
      final seen = <FunctionDeclaration>{};
      while (queue.isNotEmpty) {
        final (body, path) = queue.removeAt(0);
        final visitor = _WriteVisitor(functions)..visit(body);
        for (final (target, node) in visitor.writes) {
          if (!signals.contains(target)) continue;
          (edges[source] ??= {}).putIfAbsent(target, () => _Write(node, path));
        }
        for (final function in visitor.callees) {
          if (seen.add(function)) queue.add((function.functionExpression.body, '$path → ${function.name.lexeme}()'));
        }
      }
    }

    // A Computed depends on what it reads: an edge from each read (a signal or a Computed above it) to the Computed.
    // A Watch of a Computed that writes one of its inputs closes a cycle through it.
    for (final variable in topLevelVariables(unit)) {
      final creation = computedCreation(variable.initializer);
      if (creation == null || topLevelSignal(variable) == null) continue;
      final name = variable.name.lexeme;
      for (final read in computedReads(creation)) {
        // Only reads declared above it: a read of itself or of something below is E026, and would make a cycle
        // without a write.
        if (signals.indexOf(read) case final i when i >= 0 && i < signals.indexOf(name)) {
          (edges[read] ??= {}).putIfAbsent(name, () => _Write.read());
        }
      }
    }

    for (final component in _components(signals, edges)) {
      final first = component.first;
      final cycle = _shortestCycle(first, component.toSet(), edges);
      if (cycle == null) continue;
      // cycle: [(from, to, edge)], from == first for the first edge, to == first for the last. Every cycle has a
      // write: a Computed only reads what is declared above it. The earliest write is reported.
      int? reported;
      for (var i = 0; i < cycle.length; i++) {
        final node = cycle[i].$3.node;
        if (node != null && (reported == null || node.offset < cycle[reported].$3.node!.offset)) reported = i;
      }
      final at = reported!;
      final rotated = [...cycle.sublist(at + 1), ...cycle.sublist(0, at + 1)];
      final path =
          rotated.map((e) => e.$3.node == null ? '${e.$2} reads ${e.$1}' : '${e.$3.path} → ${e.$2}').join(' → ');
      final write = cycle[at];
      context.report(Diagnostics.reactiveCycle(path, write.$2, context.at(write.$3.node!),
          throughComputed: cycle.any((e) => e.$3.node == null)));
    }
  }

  /// Strongly connected components in declaration order of their first signal (Tarjan), each in declaration order.
  static List<List<String>> _components(List<String> signals, Map<String, Map<String, _Write>> edges) {
    final index = <String, int>{};
    final low = <String, int>{};
    final stack = <String>[];
    final onStack = <String>{};
    final result = <List<String>>[];
    void connect(String v) {
      index[v] = low[v] = index.length;
      stack.add(v);
      onStack.add(v);
      for (final w in edges[v]?.keys ?? const <String>[]) {
        if (!index.containsKey(w)) {
          connect(w);
          low[v] = low[v]! < low[w]! ? low[v]! : low[w]!;
        } else if (onStack.contains(w)) {
          low[v] = low[v]! < index[w]! ? low[v]! : index[w]!;
        }
      }
      if (low[v] == index[v]) {
        final component = <String>[];
        String w;
        do {
          w = stack.removeLast();
          onStack.remove(w);
          component.add(w);
        } while (w != v);
        component.sort((x, y) => signals.indexOf(x).compareTo(signals.indexOf(y)));
        result.add(component);
      }
    }

    for (final signal in signals) {
      if (!index.containsKey(signal)) connect(signal);
    }
    result.sort((x, y) => signals.indexOf(x.first).compareTo(signals.indexOf(y.first)));
    return result;
  }

  /// The shortest cycle from [start] back to itself within [component], as edges, or null if there is none.
  static List<(String, String, _Write)>? _shortestCycle(
      String start, Set<String> component, Map<String, Map<String, _Write>> edges) {
    final previous = <String, (String, _Write)>{};
    final queue = [start];
    while (queue.isNotEmpty) {
      final v = queue.removeAt(0);
      for (final MapEntry(key: w, value: write) in (edges[v] ?? const <String, _Write>{}).entries) {
        if (!component.contains(w)) continue;
        if (w == start) {
          final cycle = <(String, String, _Write)>[(v, w, write)];
          var at = v;
          while (at != start) {
            final (from, edge) = previous[at]!;
            cycle.insert(0, (from, at, edge));
            at = from;
          }
          return cycle;
        }
        if (!previous.containsKey(w) && w != start) {
          previous[w] = (v, write);
          queue.add(w);
        }
      }
    }
    return null;
  }
}

/// An edge of the reactive graph: a write of a signal reached from a Watch (the write itself, and the path to it,
/// `Watch(count) → bump()`), or a Computed reading a signal or Computed ([node] null).
final class _Write {
  _Write(Expression this.node, this.path);

  _Write.read()
      : node = null,
        path = '';

  final Expression? node;
  final String path;
}

/// The signal writes (`count.value = …`, `count.value++`) and the user functions called in one body, in source
/// order.
final class _WriteVisitor extends RecursiveAstVisitor<void> {
  _WriteVisitor(this.functions);

  final Map<Element?, FunctionDeclaration> functions;
  final writes = <(String, Expression)>[];
  final callees = <FunctionDeclaration>[];

  void visit(AstNode node) => node.accept(this);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (signalOfValue(node.leftHandSide) case final signal?) writes.add((signal.name, node));
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (isIncrementOrDecrement(node)) {
      if (signalOfValue(node.operand) case final signal?) writes.add((signal.name, node));
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (isIncrementOrDecrement(node)) {
      if (signalOfValue(node.operand) case final signal?) writes.add((signal.name, node));
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (functions[userFunctionOf(node)] case final function?) {
      if (!callees.contains(function)) callees.add(function);
    }
    super.visitMethodInvocation(node);
  }
}

/// A widget bound to a signal (`Led(pin: 13, on: lit)`) is driven only by it, so its methods cannot be called (E022).
final class BoundWidgetMethodRule implements ValidationRule {
  const BoundWidgetMethodRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    if (deviceOf(unit) == null) return;
    for (final call in allRootExpressions(unit).expand(subexpressions).whereType<MethodInvocation>()) {
      final target = call.target;
      if (target is! SimpleIdentifier) continue;
      final variable = topLevelDeclarationOf(target, unit);
      final creation = variable == null ? null : topLevelWidget(variable);
      if (creation == null) continue;
      final bound = creation.argumentList.arguments.where(isSignalArgument).firstOrNull?.argumentExpression;
      if (bound is! SimpleIdentifier) continue;
      context.report(Diagnostics.boundWidgetMethod(
          widgetClassOf(creation.staticType)!.name!, target.name, bound.name, context.at(call.methodName)));
    }
  }
}

/// A Computed's closure is one expression over the `.value` of signals and Computeds declared above it, literals,
/// and constants (`const` and `final` values, which cannot change): no calls, no mutable variables (E026). Reading
/// only what is declared above also rules out cycles. Every other expression rule checks the expression as usual.
final class ComputedRule implements ValidationRule {
  const ComputedRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    if (deviceOf(unit) == null) return; // E021 (or E008).
    final variables = topLevelVariables(unit).toList();
    final order = [for (final v in variables) v.declaredFragment?.element];
    for (final (index, variable) in variables.indexed) {
      final creation = computedCreation(variable.initializer);
      if (creation == null || topLevelSignal(variable) == null) continue; // Misplaced: E024.
      final closure = computedClosure(creation);
      if (closure == null) continue; // A function reference: E012.
      final expression = computedExpression(closure);
      if (expression == null) {
        context.report(Diagnostics.computedBody(context.at(closure)));
        continue;
      }
      final name = variable.name.lexeme;
      walkExpression(expression, (e) {
        if (expressionIssue(e) != null) return false; // E002/E012.
        if (e is MethodInvocation) {
          context.report(Diagnostics.computedCall('${e.methodName.name}()', context.at(e.methodName)));
          return false;
        }
        if (signalOfValue(e) case final signal?) {
          final read = switch (referenceOf(signal)) { GlobalReference(:final element) => element, _ => null };
          final at = order.indexOf(read);
          if (at == index) {
            context.report(Diagnostics.computedSelf(name, context.at(e)));
          } else if (at > index) {
            context.report(
                Diagnostics.computedForward(name, signal.name, context.at(variables[at].name).line, context.at(e)));
          }
          return false;
        }
        if (e is SimpleIdentifier) {
          if (referenceOf(e) case GlobalReference(isMutable: true)) {
            context.report(Diagnostics.computedMutable(e.name, context.at(e)));
          }
          return false;
        }
        return true;
      });
    }
  }
}
