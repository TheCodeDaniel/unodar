import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../emitter/target.dart';
import '../ir/ir.dart';
import '../semantics/types.dart';
import 'api_registry.dart';
import 'api_resolution.dart';

/// Reads binding classes (`@CppClass`) and the `external final` objects of them into registry rows (docs/SUBSET.md
/// "Binding C++ classes"), so that bindings are data, not a code path per library (docs/PLAN.md "Extension hooks").
///
/// The reader works on **valid** bindings: the binding rules (E017) are checked by the validator before anything
/// is read, and anything the reader cannot represent is a [BindingError], i.e. a compiler bug, never a silent guess.
/// A class without `@CppClass` is not a binding and is ignored (it is E005 in the user's file; `HardwareSerial` in
/// `package:unodar` is a hand-written registry row).
final class BindingReader {
  const BindingReader(this.target);

  /// Supplies the C++ facts of `@CppType` names and the default C++ types of Dart types.
  final Target target;

  /// The bindings declared in [library] itself (the user's file), limited to the classes [include] accepts (the
  /// compiler passes those without E017 problems).
  ApiBindings readLibrary(LibraryElement library, {bool Function(ClassElement cls)? include}) =>
      _read(library.classes.where(include ?? (_) => true), library.topLevelVariables);

  /// The bindings `package:unodar` exports to [library] through its imports (`Wire`, `Servo`, …).
  ApiBindings readImportedUnodar(LibraryElement library) {
    final classes = <ClassElement>[];
    final variables = <TopLevelVariableElement>[];
    for (final import in library.firstFragment.libraryImports) {
      final imported = import.importedLibrary;
      if (imported == null || !isUnodarElement(imported)) continue;
      for (final element in imported.exportNamespace.definedNames2.values) {
        switch (element) {
          case ClassElement():
            classes.add(element);
          case GetterElement(:final TopLevelVariableElement variable):
            variables.add(variable);
        }
      }
    }
    return _read(classes, variables);
  }

  ApiBindings _read(Iterable<ClassElement> classes, Iterable<TopLevelVariableElement> variables) {
    final bound = {for (final c in classes) c: _class(c)}..removeWhere((_, c) => c == null);
    return ApiBindings(
      classes: [for (final c in bound.values) c!],
      objects: [
        for (final variable in variables)
          if (_classOfObject(variable) case final cls? when bound.containsKey(cls))
            ApiObject(variable.name!,
                cppName: _string(variable, 'CppName') ?? variable.name!, className: bound[cls]!.dartName),
      ],
    );
  }

  /// The binding class an `external final` top-level variable is an object of, or null.
  ClassElement? _classOfObject(TopLevelVariableElement variable) {
    if (!variable.isExternal || !variable.isFinal) return null;
    final type = variable.type;
    return type is InterfaceType && type.element is ClassElement ? type.element as ClassElement : null;
  }

  ApiClass? _class(ClassElement element) {
    final cppName = _string(element, 'CppClass');
    if (cppName == null) return null;
    final constructors = [
      for (final c in element.constructors)
        if (c.isOriginDeclaration) c
    ];
    if (constructors.length > 1) throw BindingError(element, 'more than one constructor');
    return ApiClass(
      element.name!,
      cppName: cppName,
      header: _string(element, 'CppHeader'),
      constructor: constructors.isEmpty ? null : _parameters(constructors.single),
      methods: [
        for (final method in element.methods)
          ApiFunction(
            method.name!,
            cppName: _string(method, 'CppName') ?? method.name!,
            parameters: _parameters(method),
            returnType: _irType(method.returnType, method),
            cppReturnType: _cppResultType(method),
            convertsArguments: true,
          ),
      ],
    );
  }

  List<ApiParameter> _parameters(ExecutableElement executable) => [
        for (final parameter in executable.formalParameters) _parameter(parameter),
      ];

  ApiParameter _parameter(FormalParameterElement parameter) {
    if (parameter.isOptionalPositional) throw BindingError(parameter, 'optional positional parameter');
    final type = _irType(parameter.type, parameter);
    if (type == IrType.void_) throw BindingError(parameter, 'void parameter');
    final cppType = _string(parameter, 'CppType') ?? target.cppType(type);
    final scalar = _scalar(cppType, parameter);
    final range = cppRangeOf(parameter);
    return ApiParameter(
      parameter.name!,
      type: type,
      cppType: cppType,
      min: range?.$1 ?? scalar.min,
      max: range?.$2 ?? scalar.max,
      isNamed: parameter.isNamed,
      defaultValue: parameter.isOptionalNamed ? _defaultValue(parameter) : null,
      hasCppRange: range != null,
    );
  }

  /// The C++ result type: `@CppType` on the method, or the C++ type of a non-`int` Dart type. Null for `void` and
  /// for an `int` result without `@CppType`, whose C++ type is unknown (the emitter converts it to `int32_t`).
  String? _cppResultType(MethodElement method) {
    final type = _irType(method.returnType, method);
    final annotated = _string(method, 'CppType');
    if (annotated != null) {
      _scalar(annotated, method);
      return annotated;
    }
    if (type == IrType.void_ || type == IrType.int32) return null;
    return target.cppType(type);
  }

  CppScalarType _scalar(String cppType, Element element) =>
      target.cppScalarType(cppType) ?? (throw BindingError(element, 'unsupported C++ type $cppType'));

  IrType _irType(DartType type, Element element) =>
      irTypeOf(type) ?? (throw BindingError(element, 'unsupported type ${displayType(type)}'));

  Object _defaultValue(FormalParameterElement parameter) {
    final value = parameter.computeConstantValue();
    final result = value?.toIntValue() ?? value?.toDoubleValue() ?? value?.toBoolValue();
    return result ?? (throw BindingError(parameter, 'named parameter without a constant default'));
  }

  /// The string argument of the unodar interop annotation [annotation] on [element], or null if it has none.
  String? _string(Element element, String annotation) {
    for (final metadata in element.metadata.annotations) {
      if (interopAnnotationName(metadata) != annotation) continue;
      final DartObject? value = metadata.computeConstantValue();
      return value?.getField(_annotationFields[annotation]!)?.toStringValue() ??
          (throw BindingError(element, 'unreadable @$annotation'));
    }
    return null;
  }
}

/// The `(min, max)` of a `@CppRange` on [element], or null if it has none (or its bounds are not constant ints,
/// which E017 reports).
(int, int)? cppRangeOf(Element element) {
  for (final annotation in element.metadata.annotations) {
    if (interopAnnotationName(annotation) != 'CppRange') continue;
    final value = annotation.computeConstantValue();
    final (min, max) = (value?.getField('min')?.toIntValue(), value?.getField('max')?.toIntValue());
    return min == null || max == null ? null : (min, max);
  }
  return null;
}

/// The field holding each interop annotation's argument (`packages/unodar/lib/src/interop.dart`).
const _annotationFields = {
  'CppClass': 'name',
  'CppHeader': 'header',
  'CppName': 'name',
  'CppType': 'type',
  'CppInclude': 'header',
};

/// A binding the reader cannot represent. The validator rejects every invalid binding first (E017), so this is a
/// compiler bug.
final class BindingError extends Error {
  BindingError(this.element, this.problem);

  final Element element;
  final String problem;

  @override
  String toString() => 'BindingError: ${element.displayName}: $problem';
}
