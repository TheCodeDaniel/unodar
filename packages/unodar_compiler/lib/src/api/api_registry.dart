/// The data-driven table of supported unodar API symbols (PRD §9.10 "The API-call table should be data-driven").
///
/// Each entry maps a Dart declaration to the C++ it compiles to. The Arduino core slice and `Serial` are written
/// here by hand (their Dart declarations in `packages/unodar` carry no interop annotations); binding classes and
/// their objects, whether in `package:unodar` (Wire, Servo) or in the user's file, are read from their annotations
/// by `binding_reader.dart` and added with [ApiRegistry.withBindings]. The validator, lowering, and diagnostics
/// work from this one table.
///
/// This file is pure data with no analyzer dependency; `api_resolution.dart` connects it to resolved AST nodes.
library;

import '../ir/ir.dart';

/// One parameter of a C++ function or method: the Dart value it takes and the C++ type it is passed as.
final class ApiParameter {
  const ApiParameter(
    this.name, {
    required IrType this.type,
    required String this.cppType,
    this.min,
    this.max,
    this.isNamed = false,
    this.defaultValue,
  });

  const ApiParameter.uint8(String name, {bool isNamed = false, int? defaultValue})
      : this(name,
            type: IrType.int32, cppType: 'uint8_t', min: 0, max: 255, isNamed: isNamed, defaultValue: defaultValue);

  /// A 16-bit AVR `int`.
  const ApiParameter.int16(String name) : this(name, type: IrType.int32, cppType: 'int', min: -32768, max: 32767);

  const ApiParameter.unsignedLong(String name)
      : this(name, type: IrType.int32, cppType: 'unsigned long', min: 0, max: 4294967295);

  /// `Serial.print`'s value: any supported value, whose static type picks the C++ overload (docs/SUBSET.md
  /// "Serial").
  const ApiParameter.printable(this.name)
      : type = null,
        cppType = null,
        min = null,
        max = null,
        isNamed = false,
        defaultValue = null;

  /// The Dart parameter name.
  final String name;

  /// The Dart type, or null for a [ApiParameter.printable] value.
  final IrType? type;

  /// The C++ parameter type; null for a [ApiParameter.printable] value.
  final String? cppType;

  /// The range of [cppType] for an integer parameter, used to reject constant arguments that C++ would silently
  /// convert (E004). Null for other parameters.
  final int? min;
  final int? max;

  /// A Dart named parameter. Every parameter is passed to C++ positionally, in declaration order.
  final bool isNamed;

  /// The constant passed when a named argument is omitted (`int`, `double`, or `bool`). Null for a positional or a
  /// `required` named parameter.
  final Object? defaultValue;

  bool get isPrintable => type == null;
}

/// A function or method that compiles to a C++ call with its parameters in [parameters] order.
final class ApiFunction {
  const ApiFunction(
    this.dartName, {
    required this.cppName,
    required this.parameters,
    this.returnType = IrType.void_,
    this.cppReturnType,
  });

  final String dartName;
  final String cppName;
  final List<ApiParameter> parameters;

  /// The Dart result type.
  final IrType returnType;

  /// The C++ result type (`int`, `unsigned long`, …) the emitter converts from to keep Dart semantics, e.g.
  /// `int32_t(millis())`. Null when it is not known (a binding method without `@CppType`), in which case an
  /// integer result is always converted to `int32_t`.
  final String? cppReturnType;

  List<ApiParameter> get positionalParameters => [
        for (final p in parameters)
          if (!p.isNamed) p
      ];

  ApiParameter? namedParameter(String name) {
    for (final p in parameters) {
      if (p.isNamed && p.name == name) return p;
    }
    return null;
  }
}

/// A top-level unodar constant that compiles to a named C++ constant or macro.
final class ApiConstant {
  const ApiConstant(this.dartName, {required this.cppName});

  final String dartName;
  final String cppName;
}

/// A C++ class that Dart code reaches through objects: `HardwareSerial`, or a binding class (`@CppClass`).
final class ApiClass {
  const ApiClass(this.dartName, {required this.cppName, this.header, this.constructor, required this.methods});

  final String dartName;

  /// The C++ class name, possibly qualified (`ns::Name`).
  final String cppName;

  /// The header that declares it (`@CppHeader`), or null when `Arduino.h` does.
  final String? header;

  /// The parameters of its external constructor, or null if it has none (it is only reached through existing
  /// objects, like `TwoWire`).
  final List<ApiParameter>? constructor;

  final List<ApiFunction> methods;

  ApiFunction? method(String dartName) {
    for (final m in methods) {
      if (m.dartName == dartName) return m;
    }
    return null;
  }
}

/// An existing C++ object of an [ApiClass]: `Serial`, or an `external final` object of a binding class (`Wire`).
final class ApiObject {
  const ApiObject(this.dartName, {required this.cppName, required this.className});

  final String dartName;
  final String cppName;

  /// The [ApiClass.dartName] of its class.
  final String className;
}

/// Binding classes and objects read from annotations (`binding_reader.dart`).
final class ApiBindings {
  const ApiBindings({this.classes = const [], this.objects = const []});

  final List<ApiClass> classes;
  final List<ApiObject> objects;
}

final class ApiRegistry {
  ApiRegistry({
    required List<ApiFunction> functions,
    required List<ApiConstant> constants,
    List<ApiClass> classes = const [],
    List<ApiObject> objects = const [],
  })  : _functions = {for (final f in functions) f.dartName: f},
        _constants = {for (final c in constants) c.dartName: c},
        _classes = {for (final c in classes) c.dartName: c},
        _objects = {for (final o in objects) o.dartName: o} {
    for (final object in objects) {
      if (!_classes.containsKey(object.className)) {
        throw ArgumentError('object ${object.dartName} has unregistered class ${object.className}');
      }
    }
  }

  /// The Arduino core slice declared in `packages/unodar/lib/src/arduino_core.dart`. Parameter and result types are
  /// those of the Arduino AVR core 1.8.8 (`Arduino.h`, `wiring_digital.c`, `wiring.c`); `api_registry_test` checks
  /// each row against its Dart declaration. Phase 3 adds each function, constant, and `Serial` in the commit that
  /// enables it end to end, together with its golden (docs/PLAN.md step 5).
  factory ApiRegistry.core() => ApiRegistry(
        functions: const [
          ApiFunction('pinMode',
              cppName: 'pinMode', parameters: [ApiParameter.uint8('pin'), ApiParameter.uint8('mode')]),
          ApiFunction('digitalWrite',
              cppName: 'digitalWrite', parameters: [ApiParameter.uint8('pin'), ApiParameter.uint8('value')]),
          ApiFunction('delay', cppName: 'delay', parameters: [ApiParameter.unsignedLong('ms')]),
        ],
        constants: const [
          ApiConstant('HIGH', cppName: 'HIGH'),
          ApiConstant('LOW', cppName: 'LOW'),
          ApiConstant('OUTPUT', cppName: 'OUTPUT'),
          ApiConstant('INPUT', cppName: 'INPUT'),
          ApiConstant('INPUT_PULLUP', cppName: 'INPUT_PULLUP'),
        ],
      );

  final Map<String, ApiFunction> _functions;
  final Map<String, ApiConstant> _constants;
  final Map<String, ApiClass> _classes;
  final Map<String, ApiObject> _objects;

  /// This registry plus [bindings]. A binding may not reuse a registered Dart name.
  ApiRegistry withBindings(ApiBindings bindings) {
    for (final name in [...bindings.classes.map((c) => c.dartName), ...bindings.objects.map((o) => o.dartName)]) {
      if (_classes.containsKey(name) || _objects.containsKey(name) || _functions.containsKey(name)) {
        throw ArgumentError('binding $name is already registered');
      }
    }
    return ApiRegistry(
      functions: [..._functions.values],
      constants: [..._constants.values],
      classes: [..._classes.values, ...bindings.classes],
      objects: [..._objects.values, ...bindings.objects],
    );
  }

  ApiFunction? function(String dartName) => _functions[dartName];

  ApiConstant? constant(String dartName) => _constants[dartName];

  ApiClass? classNamed(String dartName) => _classes[dartName];

  ApiObject? object(String dartName) => _objects[dartName];

  /// The class of [object].
  ApiClass classOf(ApiObject object) => _classes[object.className]!;

  /// Supported function names in registration order, for diagnostics.
  List<String> get functionNames => List.unmodifiable(_functions.keys);

  /// Supported constant names in registration order, for diagnostics.
  List<String> get constantNames => List.unmodifiable(_constants.keys);

  /// Every Dart and C++ name the API occupies at the top level. User declarations may not reuse them (E014).
  /// Method names are not included: they only appear after `object.`.
  Set<String> get reservedNames => {
        for (final f in _functions.values) ...[f.dartName, f.cppName],
        for (final c in _constants.values) ...[c.dartName, c.cppName],
        for (final c in _classes.values) ...[c.dartName, c.cppName],
        for (final o in _objects.values) ...[o.dartName, o.cppName],
      };
}
