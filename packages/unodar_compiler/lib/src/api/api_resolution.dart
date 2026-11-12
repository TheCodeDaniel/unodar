import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'api_registry.dart';

/// Connects resolved AST nodes to [ApiRegistry] entries.
///
/// Matching is by **resolved element**, not by spelling: a user's own function named `delay`, or a `delay` from
/// another package, is not the unodar API and must not compile as Arduino's `delay`. Both the validator and the
/// lowering use these helpers, so "what counts as an API call" is defined exactly once.
extension ApiResolution on ApiRegistry {
  /// The API function invoked by [call], or null if [call] is not a direct call to a unodar API function.
  ApiFunction? resolveCall(MethodInvocation call) {
    if (call.target != null) return null;
    final element = call.methodName.element;
    if (element is! TopLevelFunctionElement || !isUnodarElement(element)) return null;
    return function(call.methodName.name);
  }

  /// The object method invoked by [call] (`Serial.print(…)`), or null if [call] is not a method call on a top-level
  /// object of a registered class.
  ResolvedMethod? resolveMethodCall(MethodInvocation call) {
    final target = call.target;
    if (target is! SimpleIdentifier || call.methodName.element is! MethodElement) return null;
    final element = target.element;
    final variable = element is GetterElement ? element.variable : element;
    if (variable is! TopLevelVariableElement) return null;
    final type = variable.type;
    if (type is! InterfaceType) return null;
    final cls = classNamed(type.element.name!);
    final method = cls?.method(call.methodName.name);
    if (cls == null || method == null) return null;
    if (isUnodarElement(variable)) {
      final object = this.object(variable.name!);
      return object == null ? null : ResolvedMethod(object.cppName, cls, method);
    }
    return null;
  }

  /// The API function or object method [call] invokes, or null.
  ApiFunction? resolveApiCall(MethodInvocation call) => resolveCall(call) ?? resolveMethodCall(call)?.method;

  /// The API constant referenced by [expression], or null if it is not a bare reference to a unodar constant.
  ApiConstant? resolveConstant(Expression expression) {
    if (expression is! SimpleIdentifier) return null;
    final element = expression.element;
    final variable = element is GetterElement ? element.variable : element;
    if (variable is! TopLevelVariableElement || !variable.isConst || !isUnodarElement(variable)) return null;
    return constant(expression.name);
  }
}

/// Whether [element] is declared in `package:unodar` (any library inside it, e.g. `src/arduino_core.dart`).
bool isUnodarElement(Element element) {
  final uri = element.library?.uri;
  return uri != null && uri.scheme == 'package' && uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'unodar';
}

/// A method call on a C++ object: the object's C++ name, its class, and the method.
final class ResolvedMethod {
  const ResolvedMethod(this.receiver, this.cls, this.method);

  final String receiver;
  final ApiClass cls;
  final ApiFunction method;
}

/// Whether [literal] is the value argument of `Serial.print`/`println` (its first positional argument), the only
/// place a string literal is allowed (docs/SUBSET.md "Serial").
bool isPrintArgument(StringLiteral literal) {
  final list = literal.parent;
  if (list is! ArgumentList || list.arguments.first != literal) return false;
  final call = list.parent;
  if (call is! MethodInvocation) return false;
  final method = call.methodName.element;
  if (method is! MethodElement || !isUnodarElement(method)) return false;
  return method.enclosingElement?.name == 'HardwareSerial' && (method.name == 'print' || method.name == 'println');
}
