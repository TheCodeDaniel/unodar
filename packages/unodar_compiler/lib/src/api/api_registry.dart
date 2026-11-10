/// The data-driven table of supported unodar API symbols (PRD §9.10 "The API-call table should be data-driven").
///
/// Each entry maps a Dart declaration in `package:unodar` to the C++ it compiles to. Adding an API function in a later
/// phase means adding a row here (and the Dart declaration in `packages/unodar`); the validator, lowering, and
/// diagnostics pick it up without code changes. Phase 3 interop bindings will extend this same table.
///
/// This file is pure data with no analyzer dependency; `api_resolution.dart` connects it to resolved AST nodes.
library;

/// A top-level unodar function that compiles to a C++ function call with the same arguments.
final class ApiFunction {
  const ApiFunction(this.dartName, {required this.cppName});

  final String dartName;
  final String cppName;
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

  /// Phase 1: the Arduino core slice declared in `packages/unodar/lib/src/arduino_core.dart`.
  factory ApiRegistry.phase1() => ApiRegistry(
        functions: const [
          ApiFunction('pinMode', cppName: 'pinMode'),
          ApiFunction('digitalWrite', cppName: 'digitalWrite'),
          ApiFunction('delay', cppName: 'delay'),
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
}
