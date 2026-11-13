import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/type.dart';

import '../api/api_registry.dart';
import '../api/api_resolution.dart';
import '../frontend/frontend.dart';
import '../ir/ir.dart';
import '../semantics/elements.dart';
import '../semantics/types.dart';
import '../semantics/walk.dart';
import '../semantics/widgets.dart';

/// Thrown when lowering meets a construct the validator should have rejected. Always a compiler bug (exit code 2),
/// never a user error: it means a validator rule and the lowering disagree about the subset.
final class LoweringError extends Error {
  LoweringError(this.message);

  final String message;

  @override
  String toString() => 'internal compiler error during lowering: $message';
}

/// Lowers a **validated** source to IR. Dart names become C++ names here, via the [ApiRegistry]; Dart operators
/// become IR operators with Dart semantics (the emitter makes them faithful in C++).
///
/// Lowering is deliberately strict: rather than guess at anything unexpected, it throws [LoweringError]. Together
/// with the validator this upholds "reject loudly, never miscompile".
final class Lowering {
  const Lowering(this.api);

  final ApiRegistry api;

  IrProgram lower(ResolvedSource source) => _Lowerer(api, source).program();
}

final class _Lowerer {
  _Lowerer(this.api, this.source);

  final ApiRegistry api;
  final ResolvedSource source;

  /// Headers of the binding classes the program uses, in order of first use.
  final _headers = <String>{};

  IrProgram program() {
    final device = deviceOf(source.unit);
    final children = device == null ? const <WidgetChild>[] : widgetChildren(device, source.unit);
    final globals = [
      for (final variable in topLevelVariables(source.unit))
        if (!_isExternal(variable)) _global(variable),
      // Widgets written in Device.children, after the top-level variables, in list order.
      for (final child in children)
        if (identical(child.element, child.creation)) _widgetObject(child.name, child.creation),
    ];
    final functions = [
      for (final function in compiledFunctions(source.unit)) _function(function),
      if (device != null) ..._entryPoints(mainFunction(source.unit)!, children),
    ];
    return IrProgram(
      sourceName: source.displayName,
      includes: [..._headers, ..._cppIncludes()],
      localIncludes: [if (device != null) 'unodar_widgets.h'],
      globals: globals,
      functions: functions,
    );
  }

  /// A widget's C++ object: `unodar::Led led(13);`. Its arguments are constants (E022), in C++ parameter order.
  IrBoundObject _widgetObject(String name, InstanceCreationExpression creation) {
    final cls = api.classOfType(creation.staticType) ?? (throw LoweringError('unregistered widget $creation'));
    final constructor = cls.constructor ?? (throw LoweringError('${cls.dartName} has no constructor'));
    return IrBoundObject(
      name: name,
      cppClass: cls.cppName,
      arguments: _apiArguments(
          ApiFunction(cls.dartName, cppName: cls.cppName, parameters: constructor), creation.argumentList),
      line: _line(creation),
    );
  }

  /// The generated `setup()` and `loop()` of a widget program (docs/SUBSET.md "Widgets: runDevice"): `setup()`
  /// starts every widget, `loop()` polls every widget that has something to poll, both in `children` order. Their
  /// `#line` is `main()`'s; each call's is the line of its entry in `children`.
  List<IrFunction> _entryPoints(FunctionDeclaration main, List<WidgetChild> children) {
    final line = _line(main.firstTokenAfterCommentAndMetadata);
    ApiWidget widget(WidgetChild child) =>
        api.widgetOfType(child.creation.staticType) ?? (throw LoweringError('unregistered widget ${child.name}'));
    return [
      IrFunction(name: 'setup', line: line, isEntryPoint: true, body: [
        for (final child in children)
          IrExpressionStatement(IrCall(widget(child).setup, const [], receiver: child.name),
              line: _line(child.element)),
      ]),
      IrFunction(name: 'loop', line: line, isEntryPoint: true, body: [
        for (final child in children)
          if (widget(child).poll != null) throw LoweringError('polled widgets arrive with Button and Every'),
      ]),
    ];
  }

  /// `external final TwoWire Wire;` names an existing C++ object: nothing is emitted for it.
  static bool _isExternal(VariableDeclaration variable) =>
      (variable.parent?.parent as TopLevelVariableDeclaration?)?.externalKeyword != null;

  /// `@CppInclude('…')` headers on the `library;` directive, in source order.
  List<String> _cppIncludes() => [
        for (final directive in source.unit.directives.whereType<LibraryDirective>())
          for (final annotation in directive.metadata)
            if (annotation.elementAnnotation case final element? when interopAnnotationName(element) == 'CppInclude')
              (annotation.arguments!.arguments.single as StringLiteral).stringValue!,
      ];

  void _usesClass(ApiClass cls) {
    if (cls.header case final header?) _headers.add(header);
  }

  int _line(SyntacticEntity node) => source.lineInfo.getLocation(node.offset).lineNumber;

  IrType _type(DartType? type, Object where) =>
      irTypeOf(type) ?? (throw LoweringError('unsupported type $type at $where'));

  IrStorage _storage(VariableDeclaration variable) => variable.isConst
      ? IrStorage.constant
      : variable.isFinal
          ? IrStorage.final_
          : IrStorage.mutable;

  IrGlobalDeclaration _global(VariableDeclaration variable) {
    final initializer = variable.initializer ?? (throw LoweringError('no initializer: ${variable.name}'));
    if (widgetCreation(initializer) case final creation?) return _widgetObject(variable.name.lexeme, creation);
    final cls = api.classOfType(variable.declaredFragment?.element.type);
    if (cls != null) {
      // A bound object: `final link = SoftSerial(10, 11);` → `SoftwareSerial link(10, 11);`.
      final constructor = cls.constructor ?? (throw LoweringError('${cls.dartName} has no constructor'));
      if (initializer is! InstanceCreationExpression) throw LoweringError('bound object ${variable.name}');
      _usesClass(cls);
      return IrBoundObject(
        name: variable.name.lexeme,
        cppClass: cls.cppName,
        arguments: _apiArguments(
            ApiFunction(cls.dartName, cppName: cls.cppName, parameters: constructor), initializer.argumentList),
        line: _line(variable.name),
      );
    }
    return IrGlobal(
      name: variable.name.lexeme,
      type: _type(variable.declaredFragment?.element.type, variable.name),
      storage: _storage(variable),
      initializer: _expression(initializer),
      line: _line(variable.name),
    );
  }

  IrFunction _function(FunctionDeclaration function) {
    final expression = function.functionExpression;
    final element = function.declaredFragment?.element ?? (throw LoweringError('unresolved ${function.name}'));
    final returnType = _type(element.returnType, function.name);
    final body = expression.body;
    final List<IrStatement> statements = switch (body) {
      BlockFunctionBody(:final block) => _statements(block.statements),
      ExpressionFunctionBody(expression: final e) when returnType == IrType.void_ => [_statementLevel(e)],
      ExpressionFunctionBody(expression: final e) => [IrReturn(_expression(e), line: _line(e))],
      _ => throw LoweringError('unsupported body of ${function.name.lexeme}'),
    };
    return IrFunction(
      name: function.name.lexeme,
      line: _line(function.firstTokenAfterCommentAndMetadata),
      returnType: returnType,
      parameters: [
        for (final parameter in expression.parameters?.parameters ?? const <FormalParameter>[])
          IrParameter(parameter.name!.lexeme, _type(parameter.declaredFragment?.element.type, parameter)),
      ],
      body: statements,
      isEntryPoint: isEntryPoint(function),
    );
  }

  // -------------------------------------------------------------------------------------------------------------
  // Statements

  /// The statements of a branch or loop body: a block's statements, or the single statement.
  List<IrStatement> _body(Statement statement) =>
      statement is Block ? _statements(statement.statements) : _statements([statement]);

  /// Lowers a statement list; `int a = 1, b = 2;` becomes one IR local per variable, in order, in the same scope.
  List<IrStatement> _statements(List<Statement> statements) => [
        for (final statement in statements)
          if (statement is VariableDeclarationStatement)
            for (final variable in statement.variables.variables) _local(variable)
          else
            _statement(statement),
      ];

  IrStatement _statement(Statement statement) {
    final line = _line(statement);
    switch (statement) {
      case Block(:final statements):
        return IrBlock(_statements(statements), line: line);
      case ExpressionStatement(:final expression):
        return _statementLevel(expression);
      case IfStatement(:final expression, :final thenStatement, :final elseStatement):
        return IrIf(
          _expression(expression),
          _body(thenStatement),
          otherwise: elseStatement == null ? null : _body(elseStatement),
          line: line,
        );
      case WhileStatement(:final condition, :final body):
        return IrWhile(_expression(condition), _body(body), line: line);
      case ForStatement(:final forLoopParts, :final body):
        return _for(forLoopParts, _body(body), line);
      case ReturnStatement(:final expression):
        return IrReturn(expression == null ? null : _expression(expression), line: line);
      case BreakStatement(label: null):
        return IrBreak(line: line);
      case ContinueStatement(label: null):
        return IrContinue(line: line);
      default:
        throw LoweringError('unsupported statement ${statement.toSource()}');
    }
  }

  IrLocal _local(VariableDeclaration variable) {
    final initializer = variable.initializer;
    return IrLocal(
      name: variable.name.lexeme,
      type: _type(variable.declaredFragment?.element.type, variable.name),
      storage: _storage(variable),
      initializer: initializer == null ? null : _expression(initializer),
      line: _line(variable.parent!.parent!),
    );
  }

  IrFor _for(ForLoopParts parts, List<IrStatement> body, int line) => switch (parts) {
        ForPartsWithDeclarations(variables: VariableDeclarationList(variables: [final v]), :final condition) => IrFor(
            initializer: _local(v),
            condition: condition == null ? null : _expression(condition),
            updates: [for (final u in parts.updaters) _statementLevel(u)],
            body: body,
            line: line,
          ),
        ForPartsWithExpression(:final initialization, :final condition, :final updaters) => IrFor(
            initializer: initialization == null ? null : _statementLevel(initialization),
            condition: condition == null ? null : _expression(condition),
            updates: [for (final u in updaters) _statementLevel(u)],
            body: body,
            line: line,
          ),
        _ => throw LoweringError('unsupported for loop ${parts.toSource()}'),
      };

  /// A call, an assignment, or `++`/`--` used as a statement.
  IrStatement _statementLevel(Expression expression) {
    final line = _line(expression);
    switch (expression) {
      case MethodInvocation() when isCppCall(expression):
        // cpp('…'): the validator guarantees a single string literal (E019).
        final literal = expression.argumentList.arguments.single.argumentExpression as StringLiteral;
        return IrRawCpp(literal.stringValue!, line: line);
      case MethodInvocation():
        return IrExpressionStatement(_call(expression), line: line);
      case AssignmentExpression(leftHandSide: SimpleIdentifier(:final name), :final operator, :final rightHandSide):
        final op = switch (operator.type) {
          TokenType.EQ => IrAssignOp.assign,
          TokenType.PLUS_EQ => IrAssignOp.add,
          TokenType.MINUS_EQ => IrAssignOp.subtract,
          _ => throw LoweringError('unsupported assignment ${expression.toSource()}'),
        };
        return IrAssign(name, op, _expression(rightHandSide), line: line);
      case PrefixExpression(operand: SimpleIdentifier(:final name), :final operator) ||
              PostfixExpression(operand: SimpleIdentifier(:final name), :final operator)
          when isIncrementOrDecrement(expression):
        return IrIncrement(name, decrement: operator.type == TokenType.MINUS_MINUS, line: line);
      default:
        throw LoweringError('unsupported statement-level expression ${expression.toSource()}');
    }
  }

  // -------------------------------------------------------------------------------------------------------------
  // Expressions

  IrType _typeOf(Expression expression) => _type(expression.staticType, expression.toSource());

  IrExpression _expression(Expression expression) {
    switch (expression) {
      case IntegerLiteral(:final value?):
        // An integer literal in a double context (`double d = 1;`) is a double in Dart.
        return (expression.staticType?.isDartCoreDouble ?? false)
            ? IrDoubleLiteral(value.toDouble())
            : IrIntLiteral(value);
      case DoubleLiteral(:final value):
        return IrDoubleLiteral(value);
      case BooleanLiteral(:final value):
        return IrBoolLiteral(value);
      case ParenthesizedExpression(expression: final inner):
        return _expression(inner);
      case SimpleIdentifier():
        return _identifier(expression);
      case PrefixExpression(:final operator, :final operand):
        return switch (operator.type) {
          TokenType.MINUS => IrUnary(IrUnaryOp.negate, _expression(operand), _typeOf(expression)),
          TokenType.BANG => IrUnary(IrUnaryOp.not, _expression(operand), IrType.bool_),
          _ => throw LoweringError('unsupported prefix ${expression.toSource()}'),
        };
      case BinaryExpression(:final operator, :final leftOperand, :final rightOperand):
        final op = _binaryOps[operator.type] ?? (throw LoweringError('unsupported operator ${operator.lexeme}'));
        return IrBinary(op, _expression(leftOperand), _expression(rightOperand), _typeOf(expression));
      case ConditionalExpression(:final condition, :final thenExpression, :final elseExpression):
        return IrConditional(
          _expression(condition),
          _expression(thenExpression),
          _expression(elseExpression),
          _typeOf(expression),
        );
      case MethodInvocation():
        return _call(expression);
      case InstanceCreationExpression(:final argumentList):
        final type =
            sizedTypeOf(expression.staticType!) ?? (throw LoweringError('constructor ${expression.toSource()}'));
        return IrConvert(type, _expression(argumentList.arguments.single.argumentExpression));
      default:
        throw LoweringError('unsupported expression ${expression.toSource()}');
    }
  }

  static const _binaryOps = {
    TokenType.PLUS: IrBinaryOp.add,
    TokenType.MINUS: IrBinaryOp.subtract,
    TokenType.STAR: IrBinaryOp.multiply,
    TokenType.TILDE_SLASH: IrBinaryOp.truncatingDivide,
    TokenType.PERCENT: IrBinaryOp.modulo,
    TokenType.SLASH: IrBinaryOp.divide,
    TokenType.EQ_EQ: IrBinaryOp.equal,
    TokenType.BANG_EQ: IrBinaryOp.notEqual,
    TokenType.LT: IrBinaryOp.less,
    TokenType.LT_EQ: IrBinaryOp.lessOrEqual,
    TokenType.GT: IrBinaryOp.greater,
    TokenType.GT_EQ: IrBinaryOp.greaterOrEqual,
    TokenType.AMPERSAND_AMPERSAND: IrBinaryOp.and,
    TokenType.BAR_BAR: IrBinaryOp.or,
  };

  IrExpression _identifier(SimpleIdentifier identifier) {
    switch (referenceOf(identifier)) {
      case UnodarConstantReference():
        final constant = api.resolveConstant(identifier) ?? (throw LoweringError('unknown constant $identifier'));
        return IrConstant(constant.cppName);
      case LocalReference() || GlobalReference():
        return IrVariable(identifier.name, _typeOf(identifier));
      default:
        throw LoweringError('unsupported reference $identifier');
    }
  }

  /// A call to an API function, an object method, or a user function.
  IrCall _call(MethodInvocation call) {
    final apiFunction = api.resolveCall(call);
    if (apiFunction != null) {
      return IrCall(
        apiFunction.cppName,
        _apiArguments(apiFunction, call.argumentList),
        type: apiFunction.returnType,
        cppResult: _cppResult(apiFunction),
      );
    }
    final method = api.resolveMethodCall(call);
    if (method != null) {
      final function = method.method;
      _usesClass(method.cls);
      if (function.parameters.firstOrNull?.isPrintable ?? false) {
        return _printCall(method.receiver, function, call.argumentList);
      }
      return IrCall(
        function.cppName,
        _apiArguments(function, call.argumentList),
        receiver: method.receiver,
        type: function.returnType,
        cppResult: _cppResult(function),
        parameterCppTypes: function.convertsArguments ? [for (final p in function.parameters) p.cppType!] : null,
      );
    }
    if (userFunctionOf(call) == null) throw LoweringError('unresolved call ${call.toSource()}');
    return IrCall(
      call.methodName.name,
      [for (final a in call.argumentList.arguments) _expression(a.argumentExpression)],
      type: _typeOf(call),
    );
  }

  /// The arguments of an API call in C++ parameter order: positional ones, then each named parameter's argument or,
  /// if omitted, its declared default.
  List<IrExpression> _apiArguments(ApiFunction function, ArgumentList list) {
    final positional = [
      for (final a in list.arguments)
        if (a is! NamedArgument) a.argumentExpression
    ];
    final named = {
      for (final a in list.arguments)
        if (a is NamedArgument) a.name.lexeme: a.argumentExpression
    };
    if (positional.length != function.positionalParameters.length) {
      throw LoweringError('argument count of ${function.dartName}');
    }
    var index = 0;
    return [
      for (final parameter in function.parameters)
        if (!parameter.isNamed)
          _expression(positional[index++])
        else if (named[parameter.name] case final argument?)
          _expression(argument)
        else
          _default(parameter),
    ];
  }

  IrExpression _default(ApiParameter parameter) => switch ((parameter.defaultValue, parameter.type)) {
        (final int value, IrType.float32) => IrDoubleLiteral(value.toDouble()),
        (final int value, _) => IrIntLiteral(value),
        (final double value, _) => IrDoubleLiteral(value),
        (final bool value, _) => IrBoolLiteral(value),
        _ => throw LoweringError('missing required named argument ${parameter.name}'),
      };

  /// `Serial.print`/`println` (docs/SUBSET.md "Serial"): the value's static type picks the C++ overload. A string
  /// literal is a flash string, `Serial.println('')` is `Serial.println()`, a bool prints `true`/`false` like Dart,
  /// and only a double takes `digits` (given or default).
  IrCall _printCall(String receiver, ApiFunction function, ArgumentList list) {
    final value = list.arguments.firstWhere((a) => a is! NamedArgument).argumentExpression;
    final digits = [
      for (final a in list.arguments)
        if (a is NamedArgument && a.name.lexeme == 'digits') a.argumentExpression
    ].firstOrNull;
    IrCall print(List<IrExpression> arguments) => IrCall(function.cppName, arguments, receiver: receiver);
    if (value is StringLiteral) {
      final text = value.stringValue ?? (throw LoweringError('interpolated print argument ${value.toSource()}'));
      if (text.isEmpty && function.cppName == 'println') return print(const []);
      return print([IrStringLiteral(text)]);
    }
    final ir = _expression(value);
    switch (ir.type) {
      case IrType.bool_:
        return print([IrConditional(ir, const IrStringLiteral('true'), const IrStringLiteral('false'), IrType.string)]);
      case IrType.float32:
        final parameter = function.namedParameter('digits')!;
        return print([ir, digits == null ? _default(parameter) : _expression(digits)]);
      case IrType.int32 || IrType.uint8 || IrType.uint16 || IrType.int16:
        if (digits != null) throw LoweringError('digits with a non-double value ${list.toSource()}');
        return print([ir]);
      case IrType.void_ || IrType.string:
        throw LoweringError('unprintable value ${value.toSource()}');
    }
  }

  /// The C++ result type of an API function or binding method, for the emitter's conversions; null for `void`.
  static IrCppResult? _cppResult(ApiFunction function) {
    if (function.returnType == IrType.void_) return null;
    final cppType = function.cppReturnType;
    return cppType == null ? const IrCppResult.unknown() : IrCppResult(cppType);
  }
}
