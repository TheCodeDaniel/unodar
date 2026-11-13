/// The single registry of diagnostic codes (PRD §9.6, §9.10 "Diagnostics are centralized").
///
/// Later phases add codes by appending entries here and a matching factory in `messages.dart`; codes are never
/// renumbered or reused, because users search for them. `docs/DIAGNOSTICS.md` documents each one.
enum DiagnosticCode {
  missingEntryPoint('E001', 'Missing required `setup()` or `loop()`'),
  unsupportedStatement('E002', 'Unsupported statement or expression kind'),
  unknownFunction('E003', 'Call to a function that is not part of the supported unodar API'),
  unsupportedArgument('E004', 'Unsupported argument (constant out of range for the Arduino parameter, or named)'),
  unsupportedDeclaration('E005', 'Unsupported top-level declaration (classes, enums, typedefs, getters, late)'),
  invalidEntrySignature('E006', 'Invalid `setup`/`loop` signature (must be `void`, no parameters)'),
  analysisError('E007', 'Dart analysis error in the source file (type error, syntax error, unresolved import)'),
  reservedMain('E008', '`main()` is reserved (widget API arrives in a later phase)'),
  unsupportedType('E009', 'Unsupported type (nullable, num, dynamic, String, …) or bool/number comparison'),
  constantOutOfRange('E010', 'Constant out of range: int32 overflow, float range, or division by zero'),
  unsupportedSignature('E011', 'Unsupported function signature (optional/named/default parameters, generics, async)'),
  functionValue('E012', 'Closure, function reference, or local function'),
  evaluationOrder('E013', 'Evaluation order would differ in C++'),
  reservedName('E014', 'Name that collides with C++ or the Arduino core'),
  nonConstantInitializer('E015', 'Top-level initializer is not a compile-time constant'),
  recursion('E016', 'Recursive function (direct or mutual)'),
  invalidBinding('E017', 'Invalid binding class or interop annotation'),
  boundObjectMisuse('E018', 'Bound object misuse'),
  cppMisuse('E019', '`cpp()` misuse'),
  cppHeap('E020', 'Heap allocation in `cpp()`');

  const DiagnosticCode(this.id, this.summary);

  /// Stable public identifier, e.g. `E003`.
  final String id;

  /// One-line description used in documentation.
  final String summary;
}
