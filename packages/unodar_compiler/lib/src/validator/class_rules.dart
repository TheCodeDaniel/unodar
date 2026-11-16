import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_resolution.dart';
import '../diagnostics/diagnostics.dart';
import '../semantics/callables.dart';
import '../semantics/classes.dart';
import '../semantics/signals.dart';
import '../semantics/types.dart';
import '../semantics/widgets.dart';
import 'rules.dart';

/// The user's own classes follow docs/SUBSET.md "Your own classes" (E027): no inheritance or modifiers, one unnamed
/// constructor without a body, no setters, operators, `late` or `external` members. A field or constructor parameter
/// of a signal, widget, object or binding type is reported here under the code of that family (E024, E022, E018).
///
/// One diagnostic per problem; a class that extends another is reported only at `extends`, because none of it can be
/// compiled.
final class ClassRule implements ValidationRule {
  const ClassRule();

  @override
  void check(CompilationUnit unit, ValidationContext context) {
    for (final declaration in unit.declarations) {
      switch (declaration) {
        case MixinDeclaration(:final name, :final mixinKeyword):
          context.report(Diagnostics.classFeature("a mixin ('${name.lexeme}')", _mixinHelp, context.at(mixinKeyword)));
        case ClassDeclaration() when userClassDeclarations(unit).contains(declaration):
          _class(declaration, context);
        default:
      }
    }
  }

  static const _mixinHelp = 'Move its fields and methods into the class that uses it, or into a class held in a field '
      '(composition).';

  void _class(ClassDeclaration declaration, ValidationContext context) {
    final name = declaration.namePart.typeName.lexeme;
    void feature(String what, String help, SyntacticEntity at) =>
        context.report(Diagnostics.classFeature(what, help, context.at(at)));

    if (declaration.extendsClause case final clause?) {
      context.report(Diagnostics.classExtends(name, clause.superclass.name.lexeme, context.at(clause.extendsKeyword)));
      return;
    }
    for (final (keyword, word) in [
      (declaration.abstractKeyword, 'abstract'),
      (declaration.sealedKeyword, 'sealed'),
      (declaration.baseKeyword, 'base'),
      (declaration.interfaceKeyword, 'interface'),
      (declaration.mixinKeyword, 'mixin'),
    ]) {
      if (keyword == null) continue;
      feature("${word == 'abstract' || word == 'interface' ? 'an' : 'a'} $word class ('$name')",
          'Remove `$word`; objects are created from plain classes, and there is no inheritance.', keyword);
    }
    if (declaration.namePart.typeParameters case final parameters?) {
      feature("a generic class ('$name')", 'Use a concrete type for each field, e.g. `int`.', parameters);
    }
    if (declaration.withClause case final clause?) {
      final mixins = clause.mixinTypes.map((t) => t.name.lexeme).join("', '");
      context.report(Diagnostics.classFeature(
          "a class with mixins ('$name' with '$mixins')", _mixinHelp, context.at(clause.withKeyword)));
    }
    if (declaration.implementsClause case final clause?) {
      final interfaces = clause.interfaces.map((t) => t.name.lexeme).join("', '");
      feature(
          "a class that implements interfaces ('$name' implements '$interfaces')",
          'Remove `implements`: objects cannot be passed around, so an interface would never be used.',
          clause.implementsKeyword);
    }

    for (final member in declaration.body.members) {
      final start = member.firstTokenAfterCommentAndMetadata;
      switch (member) {
        case FieldDeclaration(:final fields, :final externalKeyword):
          final names = fields.variables.map((v) => v.name.lexeme).join("', '");
          if (externalKeyword != null) {
            feature("an external field ('$names')", _externalHelp, start);
          } else if (fields.isLate) {
            feature("a late field ('$names')",
                'Remove `late` and initialize the field in its declaration or in the constructor.', start);
          } else {
            for (final variable in fields.variables) {
              _fieldType(variable, fields.type, context);
            }
          }
        case ConstructorDeclaration():
          _constructor(declaration, member, context);
        case MethodDeclaration(:final name, isSetter: true):
          feature("a setter ('${name.lexeme}')",
              'Assign the field directly, e.g. `object.${name.lexeme} = value;`, or write a method.', start);
        case MethodDeclaration(:final name, isOperator: true):
          feature("an operator ('${name.lexeme}')", 'Write a named method instead.', start);
        case MethodDeclaration(:final name, externalKeyword: _?):
          feature("an external member ('${name.lexeme}')", _externalHelp, start);
        case MethodDeclaration(:final name) when objectMemberNames.contains(name.lexeme):
          feature("overriding '${name.lexeme}'",
              'Remove it; there are no strings or hash maps on the device. Write a method of another name.', start);
        case MethodDeclaration():
          break; // A method or getter: compiled like a function (E011 and every body rule).
        default:
          feature('this member', 'Remove it; see "Your own classes" in docs/SUBSET.md.', start);
      }
    }
  }

  static const _externalHelp = 'Give it a body, or describe an existing C++ class with `@CppClass` (see '
      '"Binding C++ classes" in docs/SUBSET.md).';

  void _constructor(ClassDeclaration declaration, ConstructorDeclaration constructor, ValidationContext context) {
    final cls = declaration.namePart.typeName.lexeme;
    final name = constructor.name == null ? cls : '$cls.${constructor.name!.lexeme}';
    void feature(String what, String help) =>
        context.report(Diagnostics.classFeature(what, help, context.at(constructor.firstTokenAfterCommentAndMetadata)));
    if (constructor.factoryKeyword != null) {
      return feature("a factory constructor ('$name')",
          'Use the unnamed constructor; objects are created once, as top-level `final` variables.');
    }
    if (constructor.name != null) {
      return feature("a named constructor ('$name')",
          'Use one unnamed constructor, `$cls(…)`, and give it named parameters for the options.');
    }
    if (constructor.constKeyword != null) {
      return feature("a const constructor ('$name')", 'Remove `const`; objects are top-level `final` variables.');
    }
    if (constructor.externalKeyword != null) return feature("an external member ('$name')", _externalHelp);
    final parameters = constructor.parameters.parameters;
    if (parameters.any((p) => p.isOptionalPositional)) {
      final example = parameters.firstWhere((p) => p.isOptionalPositional).toSource();
      feature("a constructor with optional positional parameters ('$name')",
          'Make each parameter required, or named with a constant default value, e.g. `{$example}`.');
    }
    for (final initializer in constructor.initializers) {
      if (initializer is AssertInitializer) {
        context.report(Diagnostics.classFeature('an assert in an initializer list',
            'Remove it; there are no exceptions on the device.', context.at(initializer)));
      }
    }
    if (constructor.body case BlockFunctionBody(:final block) when block.statements.isNotEmpty) {
      context.report(Diagnostics.constructorBody(context.at(constructor.firstTokenAfterCommentAndMetadata)));
    }
    for (final parameter in parameters) {
      final element = parameter.declaredFragment?.element;
      if (element == null || parameter is FieldFormalParameter) continue; // `this.x`: the field is checked.
      final type = element.type;
      final at = context.at(parameter.type ?? parameter);
      _positionType('a parameter', type, at, context);
    }
  }

  /// A field of a signal, widget, binding or object type, or of an unsupported type.
  void _fieldType(VariableDeclaration variable, TypeAnnotation? annotation, ValidationContext context) {
    final type = variable.declaredFragment?.element.type;
    if (type == null) return;
    final at = context.at(annotation ?? variable.name);
    if (_positionType('a field', type, at, context)) return;
    if (userClassOf(type) != null || bindingClassOf(type) != null) {
      // Interim (Phase 6 step 3): composition lands in step 6.
      context.report(Diagnostics.classFeature(
          "a field of the class type '${displayType(type)}' "
              "('${variable.name.lexeme}')",
          'Declare the object at the top level instead.',
          at));
    }
  }

  /// Reports [type] in [position] if it is a signal or widget type (true), else false.
  bool _positionType(String position, DartType type, SourceLocation at, ValidationContext context) {
    if (isSignalType(type)) {
      context.report(Diagnostics.signalTypePosition(position, displayType(type), at));
      return true;
    }
    if (widgetClassOf(type) != null) {
      context.report(Diagnostics.widgetTypePosition(position, displayType(type), at));
      return true;
    }
    if (position == 'a parameter' && (userClassOf(type) != null || bindingClassOf(type) != null)) {
      context.report(userClassOf(type) != null
          ? Diagnostics.objectTypePosition(position, displayType(type), at)
          : Diagnostics.bindingTypePosition(position, displayType(type), at));
      return true;
    }
    return false;
  }
}
