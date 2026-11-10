import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

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
