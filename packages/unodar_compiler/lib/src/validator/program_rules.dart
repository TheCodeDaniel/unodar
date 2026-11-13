import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../api/api_resolution.dart';

import '../diagnostics/diagnostics.dart';
import '../emitter/cpp_names.dart';
import '../semantics/constant_evaluator.dart';
import '../semantics/elements.dart';
import '../semantics/walk.dart';
import '../semantics/widgets.dart';
import 'rules.dart';

/// Top-level initializers must be compile-time constants over earlier declarations (E015).
final class InitializerRule implements ValidationRule {
  const InitializerRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final order = [for (final variable in topLevelVariables(unit)) variable.name.lexeme];
    for (final (index, variable) in topLevelVariables(unit).indexed) {
      final name = variable.name.lexeme;
      final initializer = variable.initializer;
      // No initializer: `int? x;` and `var x;` are E009, `late`/`external` E005, anything else an analyzer error.
      if (initializer == null) continue;
      if (subexpressions(initializer).any((e) => expressionIssue(e) != null)) continue; // Reported as E002/E012.
      // A bound object (`final link = SoftSerial(10, 11);`): each constructor argument must be constant. Any other
      // initializer of a binding type is E018.
      final List<Expression> values;
      // A widget's arguments are constant-checked by E022; only the declaration order is checked here, because they
      // are emitted in its C++ declaration.
      final isWidget = widgetCreation(initializer) != null;
      if (isWidget) {
        values = [
          for (final a in (initializer as InstanceCreationExpression).argumentList.arguments) a.argumentExpression
        ];
      } else if (bindingClassOf(variable.declaredFragment?.element.type) != null) {
        if (initializer is! InstanceCreationExpression) continue;
        values = [for (final a in initializer.argumentList.arguments) a.argumentExpression];
      } else {
        values = [initializer];
      }
      for (final value in values) {
        final later = subexpressions(value).whereType<SimpleIdentifier>().where((identifier) {
          final reference = referenceOf(identifier);
          return reference is GlobalReference && order.indexOf(reference.element.name ?? '') >= index;
        }).firstOrNull;
        if (later != null) {
          context.report(Diagnostics.forwardReference(name, later.name, context.at(later)));
        } else if (!isWidget && context.constants.evaluate(value) is NotConstant) {
          context.report(Diagnostics.nonConstantInitializer(name, context.at(value)));
        }
      }
    }
  }
}

/// User-declared names must not collide with C++ or the Arduino core (E014).
final class ReservedNameRule implements ValidationRule {
  const ReservedNameRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final arduino = context.target.reservedNames;
    final api = context.unodarNames;
    void checkName(Token name) {
      final problem = reservedNameProblem(name.lexeme, api: api, arduino: arduino);
      if (problem == null) return;
      context.report(Diagnostics.reservedName(name.lexeme, problem.$1, problem.$2, context.at(name)));
    }

    for (final variable in topLevelVariables(unit)) {
      checkName(variable.name);
    }
    // A binding class's Dart name is not emitted, but it may not shadow a unodar binding (`Servo`).
    for (final declaration in bindingClassDeclarations(unit)) {
      final name = declaration.namePart.typeName;
      if (api.contains(name.lexeme)) {
        context.report(Diagnostics.reservedName(
            name.lexeme, 'it is a unodar API name', '${name.lexeme}Binding', context.at(name)));
      }
    }
    for (final function in compiledFunctions(unit)) {
      if (!isEntryPoint(function)) checkName(function.name);
      for (final parameter in function.functionExpression.parameters?.parameters ?? const <FormalParameter>[]) {
        if (parameter.name case final name?) checkName(name);
      }
      for (final statement in statementsIn(function.functionExpression.body)) {
        final list = switch (statement) {
          VariableDeclarationStatement(:final variables) => variables,
          ForStatement(forLoopParts: ForPartsWithDeclarations(:final variables)) => variables,
          _ => null,
        };
        for (final variable in list?.variables ?? const <VariableDeclaration>[]) {
          checkName(variable.name);
        }
      }
    }
  }
}

/// Why [name] is reserved, and a suggested rename (null if none fits), or null if the name is free.
(String, String?)? reservedNameProblem(String name, {required Set<String> api, required Set<String> arduino}) {
  final value = '${name}Value';
  if (cppKeywords.contains(name)) return ('it is a C++ keyword', value);
  if (api.contains(name)) return ('it is a unodar API name', value);
  // Patterns before the Arduino list, so `size_t` is explained as a reserved pattern rather than a core name.
  if (name.contains(r'$')) return (r'names containing `$` are not valid C++', null);
  if (name.startsWith('unodar_')) return ('names starting with `unodar_` are reserved for generated code', null);
  if (name.endsWith('_t')) return ('names ending in `_t` are reserved by C and C++', null);
  if (name.contains('__')) return ('names containing `__` are reserved by C and C++', null);
  if (name.startsWith(RegExp('_[A-Z]'))) {
    return ('names starting with `_` and an upper-case letter are reserved by C and C++', null);
  }
  if (arduino.contains(name)) return ('it is already defined by the Arduino core or avr-libc', value);
  if (!name.contains(RegExp('[a-z]')) && name.contains(RegExp('[A-Z]'))) {
    return ('all-caps names are reserved for C and Arduino macros', lowerCamel(name));
  }
  return null;
}

/// `LED_PIN` → `ledPin`.
String lowerCamel(String allCaps) {
  final words = allCaps.split('_').where((w) => w.isNotEmpty).map((w) => w.toLowerCase()).toList();
  if (words.isEmpty) return 'value';
  return words.first + words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

/// Rejects code whose result could depend on C++'s unspecified evaluation order (E013).
///
/// An *unsequenced group* is: the two operands of a binary operator other than `&&`/`||`; the arguments of one
/// call (two or more); the target and right-hand side of `+=`/`-=` on a mutable top-level variable. Within a group,
/// a member containing a call of any kind (user function, API function, method) may not sit next to another member
/// containing a call: hardware results depend on time and order (`micros() - micros()`). A member containing a
/// call to a **user** function may also not sit next to one reading a mutable top-level variable, which the call
/// might change; API functions and binding methods cannot change the user's variables. Each call is reported at
/// most once.
final class EvaluationOrderRule implements ValidationRule {
  const EvaluationOrderRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final reported = <MethodInvocation>{};
    void group(List<_Member> members) {
      for (final member in members) {
        final call = member.firstCall;
        if (call == null || reported.contains(call)) continue;
        for (final other in members) {
          if (identical(other, member)) continue;
          final otherCall = other.firstCall;
          final global = member.firstUserCall == null ? null : other.firstMutableGlobal;
          if (otherCall != null) {
            reported
              ..add(call)
              ..add(otherCall);
            final (first, second) = otherCall.offset < call.offset ? (otherCall, call) : (call, otherCall);
            context.report(Diagnostics.twoCalls(_callText(first), _callText(second), context.at(first.methodName)));
          } else if (global != null) {
            final userCall = member.firstUserCall!;
            reported.add(userCall);
            context.report(Diagnostics.callNextToGlobal(_callText(userCall), global, context.at(userCall.methodName)));
          } else {
            continue;
          }
          break;
        }
      }
    }

    for (final root in allRootExpressions(unit)) {
      for (final expression in subexpressions(root)) {
        switch (expression) {
          case BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
              when operator.type != TokenType.AMPERSAND_AMPERSAND && operator.type != TokenType.BAR_BAR:
            group([_Member.of(leftOperand), _Member.of(rightOperand)]);
          case MethodInvocation(:final argumentList) || InstanceCreationExpression(:final argumentList)
              when argumentList.arguments.length > 1:
            group([for (final argument in argumentList.arguments) _Member.of(argument.argumentExpression)]);
          default:
        }
      }
    }
    for (final expression in allStatementLevelExpressions(unit)) {
      if (expression case AssignmentExpression(:final operator, :final leftHandSide, :final rightHandSide)
          when operator.type == TokenType.PLUS_EQ || operator.type == TokenType.MINUS_EQ) {
        // The target of an assignment carries no element of its own; the variable is the assignment's write element.
        final written = expression.writeElement;
        final variable = written is SetterElement ? written.variable : written;
        if (variable is TopLevelVariableElement &&
            !variable.isConst &&
            !variable.isFinal &&
            !isUnodarElement(variable)) {
          group([_Member.global(leftHandSide.toSource()), _Member.of(rightHandSide)]);
        }
      }
    }
  }

  /// `next()`, `Wire.read()`.
  static String _callText(MethodInvocation call) =>
      '${call.target == null ? '' : '${call.target!.toSource()}.'}${call.methodName.name}()';
}

bool _mutableGlobal(SimpleIdentifier identifier) => switch (referenceOf(identifier)) {
      GlobalReference(:final isMutable) => isMutable,
      _ => false,
    };

/// One member of an unsequenced group: its first call, its first call to a user function, and its first read of a
/// mutable top-level variable.
final class _Member {
  _Member(this.firstCall, this.firstUserCall, this.firstMutableGlobal);

  factory _Member.of(Expression expression) {
    final all = subexpressions(expression).toList();
    final calls = all.whereType<MethodInvocation>();
    return _Member(
      calls.firstOrNull,
      calls.where((c) => userFunctionOf(c) != null).firstOrNull,
      all.whereType<SimpleIdentifier>().where(_mutableGlobal).firstOrNull?.name,
    );
  }

  factory _Member.global(String name) => _Member(null, null, name);

  final MethodInvocation? firstCall;
  final MethodInvocation? firstUserCall;
  final String? firstMutableGlobal;
}

/// Rejects recursion, direct or mutual, by finding cycles in the call graph of all user functions (E016).
final class RecursionRule implements ValidationRule {
  const RecursionRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final functions = compiledFunctions(unit).toList();
    final byName = {for (final f in functions) f.name.lexeme: f};
    final calls = {
      for (final f in functions)
        f.name.lexeme: (_CallCollector(byName.keys.toSet())..visit(f.functionExpression.body)).callees,
    };
    for (final component in _stronglyConnected(functions.map((f) => f.name.lexeme).toList(), calls)) {
      final first = component.first; // Components keep source order, so this is the first declared.
      final isCycle = component.length > 1 || calls[first]!.contains(first);
      if (!isCycle) continue;
      final path = _cycle(first, component.toSet(), calls);
      context.report(Diagnostics.recursion(first, path, context.at(byName[first]!.name)));
    }
  }

  /// Tarjan's algorithm; each component's members are returned in source order, components ordered by first member.
  static List<List<String>> _stronglyConnected(List<String> nodes, Map<String, List<String>> edges) {
    var counter = 0;
    final index = <String, int>{};
    final low = <String, int>{};
    final stack = <String>[];
    final onStack = <String>{};
    final components = <List<String>>[];
    void connect(String v) {
      index[v] = low[v] = counter++;
      stack.add(v);
      onStack.add(v);
      for (final w in edges[v]!) {
        if (!index.containsKey(w)) {
          connect(w);
          low[v] = low[v]! < low[w]! ? low[v]! : low[w]!;
        } else if (onStack.contains(w)) {
          low[v] = low[v]! < index[w]! ? low[v]! : index[w]!;
        }
      }
      if (low[v] == index[v]) {
        final component = <String>{};
        String w;
        do {
          w = stack.removeLast();
          onStack.remove(w);
          component.add(w);
        } while (w != v);
        components.add([
          for (final n in nodes)
            if (component.contains(n)) n
        ]);
      }
    }

    for (final v in nodes) {
      if (!index.containsKey(v)) connect(v);
    }
    return components..sort((a, b) => nodes.indexOf(a.first).compareTo(nodes.indexOf(b.first)));
  }

  /// The shortest call path from [start] back to itself inside [component], e.g. `[ping, pong, ping]`.
  static List<String> _cycle(String start, Set<String> component, Map<String, List<String>> edges) {
    final previous = <String, String>{};
    final queue = [start];
    while (queue.isNotEmpty) {
      final v = queue.removeAt(0);
      for (final w in edges[v]!) {
        if (!component.contains(w)) continue;
        if (w == start) {
          final path = [start];
          for (var n = v; n != start; n = previous[n]!) {
            path.insert(1, n);
          }
          return [...path, start];
        }
        if (!previous.containsKey(w) && w != start) {
          previous[w] = v;
          queue.add(w);
        }
      }
    }
    return [start, start];
  }
}

/// The user functions called anywhere in a body (any position, so even calls inside rejected code count).
final class _CallCollector extends RecursiveAstVisitor<void> {
  _CallCollector(this.userFunctions);

  final Set<String> userFunctions;
  final List<String> callees = [];

  void visit(AstNode node) => node.accept(this);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (userFunctionOf(node) != null && userFunctions.contains(node.methodName.name)) {
      if (!callees.contains(node.methodName.name)) callees.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}
