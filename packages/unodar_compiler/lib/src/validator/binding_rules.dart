import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import '../api/binding_reader.dart';
import '../diagnostics/diagnostics.dart';
import '../emitter/target.dart';
import '../frontend/frontend.dart';
import '../ir/ir.dart';
import '../semantics/elements.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import 'rules.dart';

/// Binding classes and interop annotations follow the rules of docs/SUBSET.md "Binding C++ classes" (E017).
final class BindingClassRule implements ValidationRule {
  const BindingClassRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final declaration in bindingClassDeclarations(unit)) {
      bindingClassDiagnostics(declaration, context.source, context.target).forEach(context.report);
    }
    _AnnotationPlacement(context).visit(unit);
  }
}

/// The user's classes annotated `@CppClass`.
Iterable<ClassDeclaration> bindingClassDeclarations(CompilationUnit unit) => unit.declarations
    .whereType<ClassDeclaration>()
    .where((c) => c.declaredFragment != null && hasInteropAnnotation(c.declaredFragment!.element, 'CppClass'));

/// Every E017 problem of one binding class: one diagnostic for the class itself and one per member. The compiler
/// registers only classes without problems, so the binding reader never sees an invalid one.
List<Diagnostic> bindingClassDiagnostics(ClassDeclaration declaration, ResolvedSource source, Target target) {
  final diagnostics = <Diagnostic>[];
  SourceLocation at(SyntacticEntity node) => source.locationOf(node.offset);
  final className = declaration.namePart.typeName.lexeme;
  final element = declaration.declaredFragment!.element;

  final classProblems = [
    if (declaration.extendsClause != null) 'it extends another class',
    if (declaration.implementsClause != null) 'it implements interfaces',
    if (declaration.withClause != null) 'it uses mixins',
    if (declaration.namePart.typeParameters != null) 'it has type parameters',
    if (declaration.abstractKeyword == null && !declaration.body.members.any((m) => m is ConstructorDeclaration))
      'it is not abstract but declares no external constructor',
  ];
  if (classProblems.isNotEmpty) {
    diagnostics.add(Diagnostics.bindingClass(className, englishList(classProblems), at(declaration.namePart)));
  }

  for (final member in declaration.body.members) {
    final start = member.firstTokenAfterCommentAndMetadata;
    void kind(String kind, String name, String help) =>
        diagnostics.add(Diagnostics.bindingMember(kind, name, help, at(start)));
    switch (member) {
      case FieldDeclaration(:final fields):
        kind('a field', fields.variables.map((v) => v.name.lexeme).join("', '"),
            'Remove it; the C++ object keeps its own state.');
      case MethodDeclaration(:final name, isStatic: true):
        kind('a static member', name.lexeme, 'Remove it; only methods of the C++ object can be bound.');
      case MethodDeclaration(:final name, isGetter: true) || MethodDeclaration(:final name, isSetter: true):
        kind(member.isGetter ? 'a getter' : 'a setter', name.lexeme,
            'Declare an external method instead, e.g. `external int ${name.lexeme}();`.');
      case MethodDeclaration(:final name, isOperator: true):
        kind('an operator', name.lexeme, 'Declare a named external method instead, with @CppName if needed.');
      case MethodDeclaration(:final name, externalKeyword: null):
        kind('a method with a body', name.lexeme, 'Declare it `external`; the C++ class implements it.');
      case MethodDeclaration(:final name, :final declaredFragment?):
        final problems = _signatureProblems(
            declaredFragment.element, member.parameters?.parameters ?? const [], target, member.typeParameters != null);
        if (problems.$1.isNotEmpty) {
          diagnostics.add(Diagnostics.bindingSignature(
              'method', name.lexeme, englishList(problems.$1), problems.$2, source.locationOf(name.offset)));
        }
      case ConstructorDeclaration(name: final name?):
        kind('a named constructor', '$className.${name.lexeme}',
            'Use the unnamed constructor; C++ constructors have no names.');
      case ConstructorDeclaration(externalKeyword: null) || ConstructorDeclaration(factoryKeyword: _?):
        kind('a constructor that is not external', className, 'Declare it `external $className(…);`.');
      case ConstructorDeclaration(:final declaredFragment?, :final externalKeyword?):
        final problems = _signatureProblems(declaredFragment.element, member.parameters.parameters, target, false);
        if (problems.$1.isNotEmpty) {
          diagnostics.add(Diagnostics.bindingSignature('constructor', className, englishList(problems.$1), problems.$2,
              source.locationOf(externalKeyword.next!.offset)));
        }
      default:
        kind('this member', element.name ?? className, 'Remove it.');
    }
  }
  return diagnostics;
}

/// The signature problems of a binding method or constructor, and the help to show; empty if there are none.
(List<String>, String) _signatureProblems(
    ExecutableElement executable, List<FormalParameter> parameters, Target target, bool hasTypeParameters) {
  final problems = <String>[];
  var help = 'Use the supported types (int, double, bool, Uint8, Uint16, Int16) and an accepted @CppType; see '
      '"Binding C++ classes" in docs/SUBSET.md.';
  if (hasTypeParameters) problems.add('type parameters');
  final optional = parameters.where((p) => p.isOptionalPositional).toList();
  if (optional.isNotEmpty) {
    problems.add('optional positional parameters');
    final example = optional.first.toSource();
    help = 'Make each parameter required, or named with a constant default value, e.g. `{$example}`.';
  }
  for (final parameter in executable.formalParameters) {
    final type = irTypeOf(parameter.type);
    if (type == null || type == IrType.void_) {
      problems.add("an unsupported parameter type '${displayType(parameter.type)}' ('${parameter.name}')");
      continue;
    }
    final cppType = _cppTypeOf(parameter);
    if (cppType != null) problems.addAll(_cppTypeProblems(cppType, type, "'${parameter.name}'", target));
    if (cppRangeOf(parameter) case (final min, final max)) {
      final rangeProblems = _cppRangeProblems(parameter, type, cppType ?? target.cppType(type), min, max, target);
      if (rangeProblems.isNotEmpty && optional.isEmpty) {
        help = 'Put @CppRange only on integer parameters, with min <= max inside the C++ type and around the '
            'default value, e.g. `@CppRange(33, 1059)`.';
      }
      problems.addAll(rangeProblems);
    }
  }
  if (executable is MethodElement) {
    final type = irTypeOf(executable.returnType);
    if (type == null) {
      problems.add("an unsupported return type '${displayType(executable.returnType)}'");
    } else if (_cppTypeOf(executable) case final cppType?) {
      problems.addAll(_cppTypeProblems(cppType, type, 'the result', target));
    }
  }
  return (problems, help);
}

String? _cppTypeOf(Element element) {
  for (final annotation in element.metadata.annotations) {
    if (interopAnnotationName(annotation) == 'CppType') {
      return annotation.computeConstantValue()?.getField('type')?.toStringValue();
    }
  }
  return null;
}

List<String> _cppTypeProblems(String cppType, IrType dartType, String what, Target target) {
  final scalar = target.cppScalarType(cppType);
  if (scalar == null) return ["a @CppType that is not accepted ('$cppType' on $what)"];
  final fits = switch (dartType) {
    IrType.int32 || IrType.uint8 || IrType.uint16 || IrType.int16 => scalar.kind == CppScalarKind.integer,
    IrType.float32 => scalar.kind == CppScalarKind.floatingPoint,
    IrType.bool_ => scalar.kind == CppScalarKind.boolean,
    IrType.void_ || IrType.string => false,
  };
  return fits ? const [] : ["a @CppType that does not fit the Dart type ('$cppType' on $what)"];
}

/// Problems of a `@CppRange(min, max)` on [parameter], whose C++ type is [cppType].
List<String> _cppRangeProblems(
    FormalParameterElement parameter, IrType type, String cppType, int min, int max, Target target) {
  final name = "'${parameter.name}'";
  final scalar = target.cppScalarType(cppType);
  if (!type.isInteger || scalar == null || scalar.kind != CppScalarKind.integer) {
    return ['a @CppRange on a parameter that is not an integer ($name)'];
  }
  if (min > max) return ['a @CppRange whose bounds are reversed ($min > $max on $name)'];
  if (min < scalar.min! || max > scalar.max!) {
    return [
      'a @CppRange outside its C++ type ($min to $max on $cppType $name, which holds '
          '${scalar.min} to ${scalar.max})'
    ];
  }
  final value = parameter.computeConstantValue()?.toIntValue();
  if (parameter.isOptionalNamed && value != null && (value < min || value > max)) {
    return ['a default value outside its @CppRange ($value on $name, $min to $max)'];
  }
  return const [];
}

final _cppIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final _cppQualifiedName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*$');
final _headerPath = RegExp(r'^([A-Za-z0-9_][A-Za-z0-9_.-]*/)*[A-Za-z0-9_][A-Za-z0-9_.-]*\.(h|hh|hpp)$');

/// Whether [header] is a plain header path (`Wire.h`, `utility/twi.h`): no `..`, no absolute path, no quotes.
bool isPlainHeaderPath(String header) => _headerPath.hasMatch(header) && !header.split('/').contains('..');

/// Checks where each interop annotation is and what its argument is (E017).
final class _AnnotationPlacement extends RecursiveAstVisitor<void> {
  _AnnotationPlacement(this.context);

  final ValidationContext context;

  void visit(CompilationUnit unit) => unit.accept(this);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Annotations inside a class without @CppClass are not checked: the class is E005 as a whole.
    final element = node.declaredFragment?.element;
    if (element != null && !hasInteropAnnotation(element, 'CppClass')) {
      node.metadata.forEach(visitAnnotation);
      return;
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    final annotation = node.elementAnnotation;
    final name = annotation == null ? null : interopAnnotationName(annotation);
    if (name == null) return;
    final target = node.parent;
    final allowed = switch (name) {
      'CppClass' || 'CppHeader' => target is ClassDeclaration,
      'CppName' => _isBindingMethod(target) || _isExternalObject(target),
      'CppType' => _isBindingMethod(target) || _isBindingParameter(target),
      'CppRange' => _isBindingParameter(target),
      'CppInclude' => target is LibraryDirective,
      _ => false,
    };
    if (!allowed) {
      context.report(Diagnostics.misplacedAnnotation(name, _allowedFor[name]!, context.at(node)));
      return;
    }
    if (name == 'CppRange') {
      final arguments = node.arguments?.arguments;
      final bounds = [
        if (arguments != null)
          for (final argument in arguments) argument.argumentExpression
      ];
      bool isIntLiteral(Expression e) =>
          e is IntegerLiteral || (e is PrefixExpression && e.operator.lexeme == '-' && e.operand is IntegerLiteral);
      if (bounds.length != 2 || !bounds.every(isIntLiteral)) {
        context.report(Diagnostics.annotationArgument(name, 'its bounds must be two integer literals',
            'Write them directly, e.g. `@CppRange(33, 1059)`.', context.at(node)));
      }
      return; // The bounds themselves are checked with the parameter (E017 signature problems).
    }
    final argument = node.arguments?.arguments.singleOrNull;
    final value = argument is StringLiteral ? argument.stringValue : null;
    if (value == null) {
      context.report(Diagnostics.annotationArgument(name, 'its argument must be a string literal',
          "Write the text directly, e.g. `@$name('${_example[name]}')`.", context.at(node)));
      return;
    }
    final problem = switch (name) {
      'CppClass' when !_cppQualifiedName.hasMatch(value) => "'$value' is not a valid C++ class name",
      'CppName' when !_cppIdentifier.hasMatch(value) => "'$value' is not a valid C++ identifier",
      'CppHeader' || 'CppInclude' when !isPlainHeaderPath(value) => "'$value' is not a plain header path",
      'CppType' when context.target.cppScalarType(value) == null => "'$value' is not an accepted C++ type",
      _ => null,
    };
    if (problem == null) return;
    // An unaccepted @CppType on a valid binding member is listed with that member's other problems instead.
    if (name == 'CppType') return;
    context.report(Diagnostics.annotationArgument(
        name, problem, "Use a value like `@$name('${_example[name]}')`; see docs/SUBSET.md.", context.at(node)));
  }

  static bool _isBindingMethod(AstNode? node) =>
      node is MethodDeclaration && node.parent?.parent is ClassDeclaration && node.externalKeyword != null;

  static bool _isBindingParameter(AstNode? node) {
    if (node is! FormalParameter) return false;
    final executable = node.parent?.parent;
    return (executable is MethodDeclaration || executable is ConstructorDeclaration) &&
        executable?.parent?.parent is ClassDeclaration;
  }

  static bool _isExternalObject(AstNode? node) =>
      node is TopLevelVariableDeclaration &&
      node.externalKeyword != null &&
      node.variables.variables.every((v) => bindingClassOf(v.declaredFragment?.element.type) != null);

  static const _allowedFor = {
    'CppClass': 'classes',
    'CppHeader': 'binding classes',
    'CppName': 'methods of a binding class and external objects',
    'CppType': 'parameters and methods of a binding class',
    'CppRange': 'integer parameters of a binding class',
    'CppInclude': 'the `library;` directive',
  };

  static const _example = {
    'CppClass': 'Servo',
    'CppHeader': 'Servo.h',
    'CppName': 'write',
    'CppType': 'uint8_t',
    'CppRange': '33, 1059',
    'CppInclude': 'avr/wdt.h',
  };
}

/// Values of binding types are C++ objects, which exist only as top-level `final` variables (bound objects) and
/// `external final` objects; the only thing code can do with one is call its methods (E018).
final class BoundObjectRule implements ValidationRule {
  const BoundObjectRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    final constructorInitializers = <InstanceCreationExpression>{};
    final reportedInitializers = <Expression>{};
    for (final declaration in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final element = variable.declaredFragment?.element;
        final cls = bindingClassOf(element?.type);
        if (element == null || cls == null) continue;
        final name = variable.name.lexeme;
        final initializer = variable.initializer;
        if (declaration.externalKeyword != null) {
          if (!element.isFinal) {
            context.report(
                Diagnostics.boundObjectNotFinal(name, 'external final ${cls.name} $name;', context.at(variable.name)));
          }
          continue;
        }
        if (initializer is InstanceCreationExpression &&
            initializer.constructorName.name == null &&
            initializer.staticType?.element == cls) {
          constructorInitializers.add(initializer);
        } else if (initializer != null) {
          reportedInitializers.add(initializer);
          context.report(cls.isAbstract
              ? Diagnostics.abstractBoundObject(name, cls.name!, context.at(initializer))
              : Diagnostics.boundObjectInitializer(name, cls.name!, context.at(initializer)));
        }
        if (!element.isFinal || element.isConst) {
          final example = initializer is InstanceCreationExpression
              ? 'final $name = ${initializer.toSource()};'
              : 'final $name = ${cls.name}();';
          context.report(Diagnostics.boundObjectNotFinal(name, example, context.at(variable.name)));
        }
      }
    }

    for (final function in compiledFunctions(unit)) {
      final expression = function.functionExpression;
      if (function.returnType case final type? when bindingClassOf(type.type) != null) {
        context.report(Diagnostics.bindingTypePosition('a return value', type.toSource(), context.at(type)));
      }
      for (final parameter in expression.parameters?.parameters ?? const <FormalParameter>[]) {
        final type = parameter.declaredFragment?.element.type;
        if (bindingClassOf(type) == null) continue;
        final node = _typeAnnotationOf(parameter) ?? parameter;
        context.report(Diagnostics.bindingTypePosition('a parameter', displayType(type!), context.at(node)));
      }
      for (final statement in statementsIn(expression.body)) {
        final list = switch (statement) {
          VariableDeclarationStatement(:final variables) => variables,
          ForStatement(forLoopParts: ForPartsWithDeclarations(:final variables)) => variables,
          _ => null,
        };
        for (final variable in list?.variables ?? const <VariableDeclaration>[]) {
          final type = variable.declaredFragment?.element.type;
          if (bindingClassOf(type) == null) continue;
          final at = list!.type ?? variable.name;
          context.report(Diagnostics.bindingTypePosition('a local variable', displayType(type!), context.at(at)));
        }
      }
    }

    for (final root in allRootExpressions(unit)) {
      if (reportedInitializers.contains(root)) continue;
      walkExpression(root, (expression) {
        switch (expression) {
          case InstanceCreationExpression(:final staticType)
              when bindingClassOf(staticType) != null && !constructorInitializers.contains(expression):
            if (!_isRejectedInitializer(expression)) {
              context
                  .report(Diagnostics.bindingConstructorPosition(staticType!.element!.name!, context.at(expression)));
            }
            return false;
          case SimpleIdentifier() when bindingClassOf(expression.staticType) != null:
            final reference = referenceOf(expression);
            final variable = switch (reference) {
              GlobalReference(:final element) || UnodarConstantReference(:final element) => element,
              _ => null,
            };
            // Locals and parameters of a binding type were reported at their declaration.
            if (variable != null) context.report(Diagnostics.boundObjectUse(expression.name, context.at(expression)));
            return false;
          default:
            return true;
        }
      });
    }
  }

  /// A constructor call that is the initializer of a top-level bound object already reported (not `final`, or a
  /// constructor of another class): not reported again.
  static bool _isRejectedInitializer(InstanceCreationExpression expression) {
    final variable = expression.parent;
    return variable is VariableDeclaration && variable.parent?.parent is TopLevelVariableDeclaration;
  }

  static TypeAnnotation? _typeAnnotationOf(FormalParameter parameter) => parameter.type;
}

/// Whether [type] is a binding class type: E018 reports it in any other position, so E009 skips it.
bool isBindingType(DartType? type) => bindingClassOf(type) != null;
