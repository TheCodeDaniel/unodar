import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';
import 'package:unodar_compiler/src/api/api_registry.dart';
import 'package:unodar_compiler/src/api/api_resolution.dart';
import 'package:unodar_compiler/src/emitter/target.dart';
import 'package:unodar_compiler/src/ir/ir.dart';

import '../resolve_snippet.dart';
import '../test_paths.dart';

/// The hand-written registry rows must describe the real `package:unodar` declarations, and the `@CppType` table
/// must be the one the docs promise.
void main() {
  final resolve = snippetResolver('.api_registry_tmp');
  final registry = ApiRegistry.core();

  late Map<String, Element> unodar;
  setUpAll(() async {
    final library = await resolve('''
import 'package:unodar/unodar.dart';

void setup() {}

void loop() {}
''');
    final import = library.firstFragment.libraryImports.map((i) => i.importedLibrary!).singleWhere(isUnodarElement);
    unodar = import.exportNamespace.definedNames2;
  });

  test('every registered function matches its Dart declaration (names, order, named, defaults)', () {
    for (final name in registry.functionNames) {
      final function = registry.function(name)!;
      final declaration = unodar[name];
      expect(declaration, isA<TopLevelFunctionElement>(), reason: '$name is not declared in package:unodar');
      declaration as TopLevelFunctionElement;
      expect(declaration.isExternal, isTrue, reason: name);
      expect(
        [for (final p in declaration.formalParameters) (p.name, p.isNamed, p.computeConstantValue()?.toIntValue())],
        [for (final p in function.parameters) (p.name, p.isNamed, p.defaultValue)],
        reason: name,
      );
      expect(declaration.returnType.isDartCoreInt, function.returnType == IrType.int32, reason: name);
    }
  });

  test('every registered object and class method matches its Dart declaration', () {
    for (final name in ['Serial']) {
      final object = registry.object(name)!;
      final getter = unodar[name] as GetterElement;
      final variable = getter.variable as TopLevelVariableElement;
      expect((variable.isExternal, variable.isFinal), (true, true), reason: name);
      final cls = registry.classOf(object);
      final declaration = unodar[cls.dartName] as ClassElement;
      expect(variable.type.element, same(declaration), reason: name);
      expect(declaration.methods.map((m) => m.name), cls.methods.map((m) => m.dartName), reason: cls.dartName);
      for (final method in cls.methods) {
        final dart = declaration.methods.singleWhere((m) => m.name == method.dartName);
        expect(
          [for (final p in dart.formalParameters) (p.name, p.isNamed, p.computeConstantValue()?.toIntValue())],
          [for (final p in method.parameters) (p.name, p.isNamed, p.defaultValue)],
          reason: '${cls.dartName}.${method.dartName}',
        );
      }
    }
  });

  test('every widget row matches its Dart class (constructor parameters, methods) and is a unodar:: class', () {
    for (final name in ['Led']) {
      final widget = registry.widget(name);
      expect(widget, isNotNull, reason: name);
      final cls = registry.classNamed(widget!.className)!;
      final declaration = unodar[name] as ClassElement;
      expect(cls.cppName, 'unodar::$name');
      expect(declaration.methods.map((m) => m.name), cls.methods.map((m) => m.dartName), reason: name);
      final constructor = declaration.constructors.single;
      expect(constructor.isExternal, isTrue, reason: name);
      expect([
        for (final p in constructor.formalParameters) (p.name, p.isNamed)
      ], [
        for (final p in cls.constructor!) (p.name, p.isNamed)
      ], reason: name);
    }
    expect(registry.reservedNames, containsAll(['Led', 'runDevice', 'Device', 'Uno', 'unodar']));
  });

  test('every registered constant is a const in package:unodar', () {
    for (final name in registry.constantNames) {
      final getter = unodar[name];
      expect(getter, isA<GetterElement>(), reason: name);
      expect(((getter as GetterElement).variable as TopLevelVariableElement).isConst, isTrue, reason: name);
    }
  });

  test('a registered object needs its class, and bindings may not reuse a name', () {
    const cls = ApiClass('Port', cppName: 'Port', methods: []);
    expect(() => ApiRegistry(functions: [], constants: [], objects: [ApiObject('p', cppName: 'p', className: 'Port')]),
        throwsArgumentError);
    expect(
      () => registry.withBindings(const ApiBindings(classes: [ApiClass('delay', cppName: 'Delay', methods: [])])),
      throwsArgumentError,
    );
    final withPort = registry.withBindings(
      const ApiBindings(classes: [cls], objects: [ApiObject('port', cppName: 'port1', className: 'Port')]),
    );
    expect(withPort.classOf(withPort.object('port')!), same(cls));
    expect(withPort.reservedNames, containsAll(['Port', 'port', 'port1', 'pinMode', 'HIGH']));
  });

  group('@CppType', () {
    const target = UnoTarget();

    /// The accepted list, as written in `packages/unodar/lib/src/interop.dart` and docs/SUBSET.md.
    List<String> acceptedIn(String path, RegExp sentence) {
      final text = File(path).readAsStringSync().replaceAll(RegExp(r'\n\s*(///)?\s*'), ' ');
      final list = sentence.firstMatch(text)!.group(1)!;
      return [for (final m in RegExp('`([^`]+)`').allMatches(list)) m.group(1)!];
    }

    final accepted = [
      'bool', 'float', 'double', 'int8_t', 'uint8_t', 'int16_t', 'uint16_t', 'int32_t', 'uint32_t', 'int', //
      'unsigned int', 'long', 'unsigned long', 'size_t',
    ];

    test('the target knows exactly the documented types', () {
      for (final name in accepted) {
        expect(target.cppScalarType(name)?.name, name);
      }
      for (final name in ['int64_t', 'char', 'short', 'String', 'void', 'uint8_t*']) {
        expect(target.cppScalarType(name), isNull, reason: name);
      }
      expect(acceptedIn(fromPackage('..', 'unodar', 'lib', 'src', 'interop.dart'), RegExp('Accepted: (.*?)\\.')),
          accepted);
      expect(acceptedIn(fromPackage('..', '..', 'docs', 'SUBSET.md'), RegExp(r'Accepted types: (.*?)\. ')), accepted);
    });

    test('AVR sizes: int and size_t are 16 bits, long is 32, double is float', () {
      String range(String name) => '${target.cppScalarType(name)!.min}..${target.cppScalarType(name)!.max}';
      expect(range('int'), '-32768..32767');
      expect(range('unsigned int'), '0..65535');
      expect(range('size_t'), '0..65535');
      expect(range('long'), '-2147483648..2147483647');
      expect(range('unsigned long'), '0..4294967295');
      expect(target.cppScalarType('double')!.kind, CppScalarKind.floatingPoint);
      expect(target.cppScalarType('bool')!.kind, CppScalarKind.boolean);
    });
  });
}
