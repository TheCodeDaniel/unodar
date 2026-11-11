/// The data-driven table of supported unodar API symbols (PRD §9.10 "The API-call table should be data-driven").
///
/// Each entry maps a Dart declaration in `package:unodar` to the C++ it compiles to. Adding an API function means
/// adding a row here (and the Dart declaration in `packages/unodar`); the validator, lowering, and diagnostics pick
/// it up without code changes. Phase 3 interop bindings will extend this same table.
///
/// This file is pure data with no analyzer dependency; `api_resolution.dart` connects it to resolved AST nodes.
library;

/// One parameter of an Arduino C++ function: its C++ type and the values that type holds, used to reject constant
/// arguments that C++ would silently convert (E004).
final class ApiParameter {
  const ApiParameter(this.name, {required this.cppType, required this.min, required this.max, this.isNamed = false});

  const ApiParameter.uint8(String name) : this(name, cppType: 'uint8_t', min: 0, max: 255);

  const ApiParameter.unsignedLong(String name) : this(name, cppType: 'unsigned long', min: 0, max: 4294967295);

  /// The Dart parameter name.
  final String name;
  final String cppType;
  final int min;
  final int max;

  /// A Dart named parameter. The registry models these so Phase 3 bindings can declare them; lowering passes them
  /// to C++ in registry order. No Phase 2 function has one, and a named argument is E004 until Phase 3.
  final bool isNamed;
}

/// A top-level unodar function that compiles to a C++ function call with the same arguments, in [parameters]
/// order.
final class ApiFunction {
  const ApiFunction(this.dartName, {required this.cppName, required this.parameters});

  final String dartName;
  final String cppName;
  final List<ApiParameter> parameters;

  List<ApiParameter> get positionalParameters => [
        for (final p in parameters)
          if (!p.isNamed) p
      ];
}

/// A top-level unodar constant that compiles to a named C++ constant or macro.
final class ApiConstant {
  const ApiConstant(this.dartName, {required this.cppName});

  final String dartName;
  final String cppName;
}

final class ApiRegistry {
  ApiRegistry({required List<ApiFunction> functions, required List<ApiConstant> constants})
      : _functions = {for (final f in functions) f.dartName: f},
        _constants = {for (final c in constants) c.dartName: c};

  /// The Arduino core slice declared in `packages/unodar/lib/src/arduino_core.dart`. Parameter types are those of
  /// the Arduino AVR core 1.8 (`wiring_digital.c`, `wiring.c`).
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

  ApiFunction? function(String dartName) => _functions[dartName];

  ApiConstant? constant(String dartName) => _constants[dartName];

  /// Supported function names in registration order, for diagnostics.
  List<String> get functionNames => List.unmodifiable(_functions.keys);

  /// Supported constant names in registration order, for diagnostics.
  List<String> get constantNames => List.unmodifiable(_constants.keys);

  /// Every Dart and C++ name the API occupies. User declarations may not reuse them (E014).
  Set<String> get reservedNames => {
        for (final f in _functions.values) ...[f.dartName, f.cppName],
        for (final c in _constants.values) ...[c.dartName, c.cppName],
      };
}
