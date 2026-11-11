import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';

import '../api/api_registry.dart';
import '../diagnostics/diagnostics.dart';
import '../emitter/target.dart';
import '../frontend/frontend.dart';
import '../semantics/constant_evaluator.dart';
import '../semantics/walk.dart';

export 'body_rules.dart';
export 'declaration_rules.dart';
export 'program_rules.dart';

/// Shared state for one validation run. Rules only ever *add* diagnostics; none of them stops the run, so the user
/// sees every problem at once (PRD §9.5 step 2).
final class ValidationContext {
  ValidationContext(this.source, this.api, this.target);

  final ResolvedSource source;
  final ApiRegistry api;
  final Target target;
  final ConstantEvaluator constants = const ConstantEvaluator();
  final List<Diagnostic> diagnostics = [];

  void report(Diagnostic diagnostic) => diagnostics.add(diagnostic);

  SourceLocation at(SyntacticEntity node) => source.locationOf(node.offset);
}

/// One independent subset check (PRD §9.10 "Validator rules are composable").
///
/// Each rule owns one concern and reports one family of codes. The subset grows by relaxing or replacing an
/// individual rule, not by editing a monolithic walker. All rules traverse the program through
/// `semantics/walk.dart`, so they agree on which positions exist.
abstract interface class ValidationRule {
  void check(CompilationUnit unit, ValidationContext context);
}

/// Offsets of the names of unresolved, target-less calls written as statements (`tone(8, 440);`) anywhere in the
/// program.
///
/// [ApiCallRule] reports each of these as E003, so the compiler lets the analyzer's error at the same offset through
/// to validation instead of stopping with E007.
Set<int> unresolvedCallStatementOffsets(CompilationUnit unit) => {
      for (final expression in allStatementLevelExpressions(unit))
        if (expression case MethodInvocation(target: null, :final methodName) when methodName.element == null)
          methodName.offset,
    };
