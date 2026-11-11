import '../api/api_registry.dart';
import '../diagnostics/diagnostics.dart';
import '../emitter/target.dart';
import '../frontend/frontend.dart';
import 'rules.dart';

/// PRD §9.5 step 2: enforces the subset by running every rule and collecting all diagnostics.
final class Validator {
  const Validator({required this.api, this.target = const UnoTarget(), this.rules = defaultRules});

  /// The Phase 2 subset. Order does not affect the result (diagnostics are sorted), only readability.
  static const defaultRules = <ValidationRule>[
    // Declarations.
    DirectiveRule(),
    TopLevelDeclarationRule(),
    EntryPointSignatureRule(),
    FunctionSignatureRule(),
    DeclaredTypeRule(),
    InitializerRule(),
    ReservedNameRule(),
    // Bodies.
    StatementRule(),
    ExpressionRule(),
    ExpressionTypeRule(),
    ApiCallRule(),
    ArgumentRule(),
    ConstantRangeRule(),
    // Whole program.
    EvaluationOrderRule(),
    RecursionRule(),
  ];

  final ApiRegistry api;
  final Target target;
  final List<ValidationRule> rules;

  /// Returns every subset violation in [source], sorted. Empty means the source can be lowered.
  List<Diagnostic> validate(ResolvedSource source) {
    final context = ValidationContext(source, api, target);
    for (final rule in rules) {
      rule.check(source.unit, context);
    }
    return sortDiagnostics(context.diagnostics);
  }
}
