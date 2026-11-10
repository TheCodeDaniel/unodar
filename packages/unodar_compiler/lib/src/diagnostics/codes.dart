/// The single registry of diagnostic codes (PRD §9.6, §9.10 "Diagnostics are centralized").
///
/// Later phases add codes by appending entries here and a matching factory in `messages.dart`; codes are never
/// renumbered or reused, because users search for them. `docs/DIAGNOSTICS.md` documents each one.
enum DiagnosticCode {
  missingEntryPoint('E001', 'Missing required `setup()` or `loop()`'),
  unsupportedStatement('E002', 'Unsupported statement or expression kind'),
  unknownFunction('E003', 'Call to a function that is not part of the supported unodar API'),
  unsupportedArgument('E004', 'Unsupported argument (only int literals and unodar constants allowed)'),
  unsupportedDeclaration('E005', 'Unsupported top-level declaration (variables, classes, extra functions)'),
  invalidEntrySignature('E006', 'Invalid `setup`/`loop` signature (must be `void`, no parameters)'),
  analysisError('E007', 'Dart analysis error in the source file (type error, syntax error, unresolved import)'),
  reservedMain('E008', '`main()` is reserved (widget API arrives in a later phase)');

  const DiagnosticCode(this.id, this.summary);

  /// Stable public identifier, e.g. `E003`.
  final String id;

  /// One-line description used in documentation.
  final String summary;
}
