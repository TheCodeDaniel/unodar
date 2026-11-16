import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../api/api_resolution.dart';

import '../diagnostics/diagnostics.dart';
import '../emitter/cpp_names.dart';
import '../semantics/callables.dart';
import '../semantics/classes.dart';
import '../semantics/constant_evaluator.dart';
import '../semantics/elements.dart';
import '../semantics/enums.dart';
import '../semantics/signals.dart';
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
      // A Computed: its expression is checked by E026 (what it may read, in which order), not as a constant.
      if (computedCreation(initializer) != null) continue;
      // A widget handle used as a value is E022, a signal used as a value E024.
      if (subexpressions(initializer).any((e) =>
          e is SimpleIdentifier &&
          (widgetClassOf(e.staticType) != null || (isSignalType(e.staticType) && !_isSignalArgumentName(e))))) {
        continue;
      }
      // A bound object (`final link = SoftSerial(10, 11);`): each constructor argument must be constant. Any other
      // initializer of a binding type is E018.
      final List<Expression> values;
      // A widget's arguments are constant-checked by E022; only the declaration order is checked here, because they
      // are emitted in its C++ declaration.
      final isWidget = widgetCreation(initializer) != null;
      final signal = signalCreation(initializer);
      if (signal != null) {
        // A signal (`final count = Signal(0);`): its initial value must be constant (E015).
        values = [signalInitialValue(signal)];
      } else if (isWidget) {
        values = [
          for (final a in (initializer as InstanceCreationExpression).argumentList.arguments) a.argumentExpression
        ];
      } else if (bindingClassOf(variable.declaredFragment?.element.type) != null) {
        if (initializer is! InstanceCreationExpression) continue;
        values = [for (final a in initializer.argumentList.arguments) a.argumentExpression];
      } else if (userClassOf(variable.declaredFragment?.element.type) case final cls?) {
        // An object (`final left = Counter(1);`): its class must be declared above it, its arguments constant. Any
        // other initializer is E018.
        if (objectCreation(initializer) == null) continue;
        final creation = initializer as InstanceCreationExpression;
        final declaration = cls.firstFragment.nameOffset;
        if (declaration != null && declaration > variable.offset) {
          context.report(Diagnostics.forwardReference(name, cls.name!, context.at(creation.constructorName)));
          continue;
        }
        values = [for (final a in creation.argumentList.arguments) a.argumentExpression];
      } else {
        values = [initializer];
      }
      // `const early = Later.size + 1;` with `Later` declared below: C++ needs the class first.
      if (values.map((v) => _laterStatic(v, variable.offset)).nonNulls.firstOrNull case (final node, final cls)) {
        context.report(Diagnostics.forwardReference(name, cls, context.at(node)));
        continue;
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

/// A static member (`Later.size`) in [root] of a user class declared after [offset]: the node and the class name.
/// Fields of [exclude] (the class whose own body is checked) are not "a class declared below": see
/// [_staticDeclaredBelow].
(Expression, String)? _laterStatic(Expression root, int offset, {Element? exclude}) {
  for (final e in subexpressions(root)) {
    final field = staticFieldOf(e);
    final declared = field?.enclosingElement.firstFragment.nameOffset;
    if (field != null && field.enclosingElement != exclude && declared != null && declared > offset) {
      return (e, field.enclosingElement.name!);
    }
  }
  return null;
}

/// A static field of [cls] that [root] reads (`step` or `Timing.step`) and that is declared below [offset] in the
/// class: C++ needs a static member's initializer to see what it uses, so it is E015.
Expression? _staticDeclaredBelow(Expression root, Element? cls, int offset) {
  for (final e in subexpressions(root)) {
    final field = switch (e) {
      SimpleIdentifier() => switch (referenceOf(e)) {
          FieldReference(:final element) when element.isStatic => element,
          _ => null,
        },
      _ => staticFieldOf(e),
    };
    final declared = field?.firstFragment.nameOffset;
    if (field != null && field.enclosingElement == cls && declared != null && declared > offset) return e;
  }
  return null;
}

/// What the user's classes compile must be constant (E015): field initializers over constants, initializer-list
/// values over constants and the constructor's parameters, and nothing declared below the class.
final class ClassInitializerRule implements ValidationRule {
  const ClassInitializerRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final globals = {
      for (final variable in topLevelVariables(unit)) variable.declaredFragment?.element: variable.offset
    };
    for (final declaration in userClassDeclarations(unit).where((c) => c.extendsClause == null)) {
      final cls = declaration.namePart.typeName.lexeme;
      bool skip(Expression root) => subexpressions(root).any((e) =>
          expressionIssue(e) != null ||
          isSignalType(e.staticType) ||
          widgetClassOf(e.staticType) != null ||
          (e is! InstanceCreationExpression && isObjectType(e.staticType)));
      void check(Expression root, String what, {bool parameters = false}) {
        // A member object created in place: each constructor argument follows the same rule.
        if (root is InstanceCreationExpression && isObjectType(root.staticType)) {
          final member = switch (root.parent) {
            VariableDeclaration(:final name) => name.lexeme,
            ConstructorFieldInitializer(:final fieldName) => fieldName.name,
            _ => '?',
          };
          for (final argument in root.argumentList.arguments) {
            check(argument.argumentExpression, "an argument of the member object '$member'", parameters: parameters);
          }
          return;
        }
        if (skip(root)) return;
        final later = subexpressions(root).whereType<SimpleIdentifier>().where((identifier) {
          final reference = referenceOf(identifier);
          return reference is GlobalReference && (globals[reference.element] ?? 0) > declaration.offset;
        }).firstOrNull;
        if (later != null) {
          context.report(Diagnostics.classForwardReference(cls, later.name, context.at(later)));
          return;
        }
        // `Later.size`: a static member of a class declared below this one.
        if (_laterStatic(root, declaration.offset, exclude: declaration.declaredFragment?.element)
            case (final node, final name)) {
          context.report(Diagnostics.classForwardReference(cls, name, context.at(node)));
          return;
        }
        final constant = subexpressions(root).every((e) => switch (e) {
              MethodInvocation() => false,
              SimpleIdentifier() when parameters && constructorParameterOf(e) != null => true,
              SimpleIdentifier() ||
              PrefixedIdentifier() ||
              PropertyAccess() =>
                context.constants.evaluate(e) is! NotConstant,
              _ => true,
            });
        if (!constant) context.report(Diagnostics.nonConstantClassInitializer(what, context.at(root)));
      }

      for (final member in declaration.body.members) {
        switch (member) {
          case FieldDeclaration(:final fields):
            // A member object's class must be declared above (C++ needs its complete type).
            final memberClass = userClassOf(fields.variables.first.declaredFragment?.element.type);
            final memberOffset = memberClass?.firstFragment.nameOffset;
            // (A class holding itself is E027.)
            if (memberOffset != null &&
                memberOffset > declaration.offset &&
                memberClass != declaration.declaredFragment?.element) {
              context.report(Diagnostics.classForwardReference(
                  cls, memberClass!.name!, context.at(fields.type ?? fields.variables.first.name)));
              continue;
            }
            for (final variable in fields.variables) {
              final initializer = variable.initializer;
              if (initializer != null && member.isStatic) {
                final below = _staticDeclaredBelow(initializer, declaration.declaredFragment?.element, variable.offset);
                if (below != null) {
                  final name = below is PrefixedIdentifier ? below.identifier.name : below.toSource();
                  context.report(Diagnostics.staticForwardReference(variable.name.lexeme, name, context.at(below)));
                  continue;
                }
              }
              if (initializer != null) {
                check(initializer,
                    "the initializer of ${member.isStatic ? 'static ' : ''}field '${variable.name.lexeme}'");
              }
            }
          case ConstructorDeclaration(name: null, factoryKeyword: null, :final initializers):
            for (final initializer in initializers.whereType<ConstructorFieldInitializer>()) {
              check(initializer.expression, "the value of '${initializer.fieldName.name}' in the initializer list",
                  parameters: true);
            }
          default:
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
    _checkGeneratedCallbackNames(unit, context);
    // A binding class's Dart name is not emitted, but it may not shadow a unodar binding (`Servo`).
    for (final declaration in bindingClassDeclarations(unit)) {
      final name = declaration.namePart.typeName;
      if (api.contains(name.lexeme)) {
        context.report(Diagnostics.reservedName(
            name.lexeme, 'it is a unodar API name', '${name.lexeme}Binding', context.at(name)));
      }
    }
    // An enum and its values become C++ names; Arduino's macros ignore C++ scopes, even `Mode::min`.
    for (final declaration in userEnumDeclarations(unit)) {
      checkName(declaration.namePart.typeName);
      for (final constant in declaration.body.constants) {
        checkName(constant.name);
      }
    }
    // A class, its fields and its constructor's parameters become C++ names; Arduino's macros ignore C++ scopes.
    for (final declaration in userClassDeclarations(unit)) {
      checkName(declaration.namePart.typeName);
      for (final member in declaration.body.members) {
        switch (member) {
          case FieldDeclaration(:final fields):
            for (final variable in fields.variables) {
              checkName(variable.name);
            }
          case ConstructorDeclaration(:final parameters):
            for (final parameter in parameters.parameters) {
              if (parameter is! FieldFormalParameter && parameter.name != null) checkName(parameter.name!);
            }
          default:
        }
      }
    }
    for (final function in compiledCallables(unit)) {
      if (function.function == null || !isEntryPoint(function.function!)) checkName(function.name);
      for (final parameter in function.parameters?.parameters ?? const <FormalParameter>[]) {
        if (parameter.name case final name?) checkName(name);
      }
    }
    // A Watch callback's parameter becomes a C++ parameter.
    for (final callback in widgetCallbacks(unit)) {
      for (final parameter in callback.parameters?.parameters ?? const <FormalParameter>[]) {
        if (parameter.name case final name?) checkName(name);
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
          checkName(variable.name);
        }
      }
    }
  }
}

/// A top-level widget whose callback would get the same C++ name as the callback of a widget written in
/// `Device.children`: `button_0`'s is `unodar_button_0_onPressed`, and so is that of the first inline `Button`
/// (object `unodar_button_0`). Reported at the top-level widget, the name the user chose (E014); only real clashes
/// are reported, so `button_0` stays usable for a Led or when there is no inline Button.
void _checkGeneratedCallbackNames(CompilationUnit unit, ValidationContext context) {
  final device = deviceOf(unit);
  if (device == null) return;
  final inline = <String, InstanceCreationExpression>{
    for (final child in widgetChildren(device, unit))
      if (child.name.startsWith('unodar_'))
        if (callbackOf(child.creation) case final closure?) callbackFunctionName(child.name, closure): child.creation,
  };
  for (final variable in topLevelVariables(unit)) {
    final closure = switch (topLevelWidget(variable)) { final creation? => callbackOf(creation), null => null };
    if (closure == null) continue;
    final name = variable.name.lexeme;
    final generated = callbackFunctionName(name, closure);
    final other = inline[generated];
    if (other == null) continue;
    context.report(Diagnostics.reservedName(
        name,
        'its callback would have the same C++ name, $generated, as the callback of the '
        '${widgetClassOf(other.staticType)!.name} on line ${context.at(other).line}',
        withoutUnderscores(name),
        context.at(variable.name)));
  }
}

/// `button_0` → `button0`, `my_led_2` → `myLed2`, `_led_1` → `led1`.
String withoutUnderscores(String name) {
  final camel = name.replaceAllMapped(RegExp('_+(.?)'), (match) => match.group(1)!.toUpperCase());
  return camel.isEmpty ? 'widget' : camel[0].toLowerCase() + camel.substring(1);
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
    final reported = <AstNode>{};
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
            context.report(Diagnostics.twoCalls(_callText(first), _callText(second), context.at(_callNode(first))));
          } else if (global != null) {
            final userCall = member.firstUserCall!;
            reported.add(userCall);
            context.report(Diagnostics.callNextToGlobal(_callText(userCall), global, context.at(_callNode(userCall))));
          } else {
            continue;
          }
          break;
        }
      }
    }

    for (final root in allRootExpressions(unit)) {
      // Not inside a Computed: it may not call anything (E026), so its operands have no order to keep.
      final inComputed = <Expression>{};
      walkExpression(root, (e) {
        if (e is FunctionExpression && isComputedClosure(e)) {
          inComputed.addAll(subexpressions(e));
          return false;
        }
        return true;
      });
      for (final expression in subexpressions(root).where((e) => !inComputed.contains(e))) {
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
        } else if (signalOfValue(leftHandSide) != null ||
            fieldAccessOf(leftHandSide) != null ||
            thisFieldOf(leftHandSide) != null ||
            staticFieldOf(leftHandSide) != null ||
            (leftHandSide is SimpleIdentifier && referenceOf(leftHandSide) is FieldReference)) {
          // `count.value += next()` is `count.set(count.value() + next())`: the read and the call are unsequenced.
          group([_Member.global(leftHandSide.toSource()), _Member.of(rightHandSide)]);
        }
      }
    }
  }

  /// `next()`, `Wire.read()`, or a getter as written (`meter.big`).
  static String _callText(AstNode call) => call is MethodInvocation
      ? '${call.target == null ? '' : '${call.target!.toSource()}.'}${call.methodName.name}()'
      : call.toSource();

  /// Where a call is reported: a method's name, or the getter read.
  static AstNode _callNode(AstNode call) => call is MethodInvocation ? call.methodName : call;
}

/// `count` in `Watch(count, …)`: a widget's signal argument, checked for declaration order like other arguments.
bool _isSignalArgumentName(SimpleIdentifier identifier) {
  final argument = argumentOf(identifier);
  return argument != null && isSignalArgument(argument);
}

bool _mutableGlobal(SimpleIdentifier identifier) => switch (referenceOf(identifier)) {
      GlobalReference(:final isMutable) || FieldReference(:final isMutable) => isMutable,
      _ => false,
    };

/// One member of an unsequenced group: its first call, its first call to a user function, and its first read of a
/// mutable top-level variable.
final class _Member {
  _Member(this.firstCall, this.firstUserCall, this.firstMutableGlobal);

  factory _Member.of(Expression expression) {
    final all = subexpressions(expression).toList();
    // Method invocations, and getter reads of the user's classes (a getter is a call).
    final calls = all.where((e) => e is MethodInvocation || calleeOf(e) != null);
    return _Member(
      calls.firstOrNull,
      calls.where((c) => calleeOf(c) != null).firstOrNull,
      // A signal's `.value` is mutable top-level state too.
      [
        for (final e in all)
          if (e is SimpleIdentifier && _mutableGlobal(e))
            e.name
          else if (signalOfValue(e) != null ||
              (fieldAccessOf(e)?.isMutable ?? false) ||
              !(staticFieldOf(e)?.isFinal ?? true) ||
              !(thisFieldOf(e)?.isFinal ?? true))
            e.toSource(),
      ].firstOrNull,
    );
  }

  factory _Member.global(String name) => _Member(null, null, name);

  final AstNode? firstCall;
  final AstNode? firstUserCall;
  final String? firstMutableGlobal;
}

/// Rejects recursion, direct or mutual, by finding cycles in the call graph of all user functions (E016).
final class RecursionRule implements ValidationRule {
  const RecursionRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final functions = compiledCallables(unit);
    final byName = {for (final f in functions) f.displayName: f};
    final names = {for (final f in functions) f.element: f.displayName};
    final calls = {
      for (final f in functions) f.displayName: (_CallCollector(names)..visit(f.body)).callees,
    };
    for (final component in _stronglyConnected(functions.map((f) => f.displayName).toList(), calls)) {
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

/// The user functions, methods and getters called anywhere in a body (any position, so even calls inside rejected
/// code count), by display name.
final class _CallCollector extends RecursiveAstVisitor<void> {
  _CallCollector(this.names);

  final Map<Element?, String> names;
  final List<String> callees = [];

  void visit(AstNode node) => node.accept(this);

  void _call(AstNode node) {
    if (names[calleeOf(node)] case final name? when !callees.contains(name)) callees.add(name);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _call(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _call(node);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _call(node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _call(node);
    super.visitSimpleIdentifier(node);
  }
}
