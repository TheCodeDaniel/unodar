import '../api/api_registry.dart';
import '../diagnostics/diagnostics.dart';
import '../frontend/frontend.dart';
import 'rules.dart';

/// PRD §9.5 step 2: enforces the subset by running every rule and collecting all diagnostics.
final class Validator {
  const Validator({required this.api, this.rules = phase1Rules});

  /// The Phase 1 subset. Order does not affect the result (diagnostics are sorted), only readability.
  static const phase1Rules = <ValidationRule>[
    DirectiveRule(),
    TopLevelDeclarationRule(),
    EntryPointSignatureRule(),
    StatementRule(),
    ApiCallRule(),
    ArgumentRule(),
  ];

  final ApiRegistry api;
  final List<ValidationRule> rules;

  /// Returns every subset violation in [source], sorted. Empty means the source can be lowered.
  List<Diagnostic> validate(ResolvedSource source) {
    final context = ValidationContext(source, api);
    for (final rule in rules) {
      rule.check(source.unit, context);
    }
    return sortDiagnostics(context.diagnostics);
  }
}
