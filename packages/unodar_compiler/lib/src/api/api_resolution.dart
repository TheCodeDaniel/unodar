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
    if (isUnodarElement(variable) || variable.isExternal) {
      final object = this.object(variable.name!);
      return object == null ? null : ResolvedMethod(object.cppName, cls, method);
    }
    // A bound object declared in the user's file: its C++ name is its Dart name.
    return ResolvedMethod(variable.name!, cls, method);
  }

  /// The registered class of a binding type, or null.
  ApiClass? classOfType(DartType? type) {
    final element = bindingClassOf(type);
    return element == null ? null : classNamed(element.name!);
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

/// Whether [call] is the escape hatch `cpp('…')` from `package:unodar`.
bool isCppCall(MethodInvocation call) {
  final element = call.methodName.element;
  return call.target == null && element is TopLevelFunctionElement && isUnodarElement(element) && element.name == 'cpp';
}

/// Whether [literal] is the argument of `cpp(…)` (checked further by E019/E020).
bool isCppArgument(StringLiteral literal) {
  final list = literal.parent;
  final call = list?.parent;
  return list is ArgumentList && call is MethodInvocation && isCppCall(call);
}

/// Whether [literal] is the value argument of `Serial.print`/`println` (its first positional argument), where a
/// string literal is allowed (docs/SUBSET.md "Serial"); the other place is `cpp('…')`.
bool isPrintArgument(StringLiteral literal) {
  final list = literal.parent;
  if (list is! ArgumentList || list.arguments.first != literal) return false;
  final call = list.parent;
  if (call is! MethodInvocation) return false;
  final method = call.methodName.element;
  if (method is! MethodElement || !isUnodarElement(method)) return false;
  return method.enclosingElement?.name == 'HardwareSerial' && (method.name == 'print' || method.name == 'println');
}

/// The name of the unodar interop annotation [annotation] (`CppClass`, `CppHeader`, `CppName`, `CppType`,
/// `CppRange`, `CppInclude`), or null if it is not one.
String? interopAnnotationName(ElementAnnotation annotation) {
  final element = annotation.element;
  final cls = element is ConstructorElement ? element.enclosingElement : null;
  if (cls is! ClassElement || !isUnodarElement(cls)) return null;
  return const {'CppClass', 'CppHeader', 'CppName', 'CppType', 'CppRange', 'CppInclude'}.contains(cls.name)
      ? cls.name
      : null;
}

/// Whether [element] carries the unodar interop annotation [name].
bool hasInteropAnnotation(Element element, String name) =>
    element.metadata.annotations.any((a) => interopAnnotationName(a) == name);

/// Whether [element] is a binding class: annotated `@CppClass` (in `package:unodar` or the user's file), or unodar's
/// `HardwareSerial`. Values of these types are C++ objects (docs/SUBSET.md "Binding C++ classes").
bool isBindingClass(Element? element) =>
    element is ClassElement &&
    (hasInteropAnnotation(element, 'CppClass') || (isUnodarElement(element) && element.name == 'HardwareSerial'));

/// The binding class [type] names, or null.
ClassElement? bindingClassOf(DartType? type) =>
    type is InterfaceType && isBindingClass(type.element) ? type.element as ClassElement : null;
