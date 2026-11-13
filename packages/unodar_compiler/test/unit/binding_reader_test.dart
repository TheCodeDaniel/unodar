import 'package:test/test.dart';
import 'package:unodar_compiler/src/api/api_registry.dart';
import 'package:unodar_compiler/src/api/binding_reader.dart';
import 'package:unodar_compiler/src/emitter/target.dart';

import '../resolve_snippet.dart';

/// The binding reader turns `@CppClass` declarations into registry rows (docs/SUBSET.md "Binding C++ classes").
void main() {
  final resolve = snippetResolver('.binding_reader_tmp');
  const reader = BindingReader(UnoTarget());

  const program = '''
import 'package:unodar/unodar.dart';

void setup() {}

void loop() {}
''';

  /// A readable summary of a parameter: `name: cppType [min..max]`, plus `named = default`.
  String describe(ApiParameter p) => [
        '${p.name}: ${p.type?.name} as ${p.cppType}',
        if (p.min != null) '[${p.min}..${p.max}]',
        if (p.hasCppRange) '@CppRange',
        if (p.isNamed) 'named${p.defaultValue == null ? ' required' : ' = ${p.defaultValue}'}',
      ].join(' ');

  String signature(ApiFunction f) => '${f.cppName}(${f.parameters.map(describe).join(', ')}) '
      '-> ${f.returnType.name}${f.cppReturnType == null ? '' : ' as ${f.cppReturnType}'}';

  group('package:unodar', () {
    late ApiBindings bindings;
    setUpAll(() async => bindings = reader.readImportedUnodar(await resolve(program)));

    ApiClass classNamed(String name) => bindings.classes.singleWhere((c) => c.dartName == name);

    test('reads exactly the binding classes and their objects; Serial is a hand-written row', () {
      expect(bindings.classes.map((c) => c.dartName), unorderedEquals(['TwoWire', 'Servo']));
      expect(bindings.objects.map((o) => (o.dartName, o.cppName, o.className)), [('Wire', 'Wire', 'TwoWire')]);
    });

    test('TwoWire: Wire.h, no constructor, C++ types from @CppType', () {
      final wire = classNamed('TwoWire');
      expect((wire.cppName, wire.header, wire.constructor), ('TwoWire', 'Wire.h', null));
      expect(wire.methods.map(signature), [
        'begin() -> void_',
        'setClock(frequency: int32 as uint32_t [0..4294967295]) -> void_',
        'beginTransmission(address: int32 as uint8_t [0..255]) -> void_',
        'write(value: int32 as uint8_t [0..255]) -> int32 as size_t',
        'endTransmission() -> int32 as uint8_t',
        'requestFrom(address: int32 as int [-32768..32767], quantity: int32 as int [-32768..32767]) '
            '-> int32 as uint8_t',
        'available() -> int32 as int',
        'read() -> int32 as int',
      ]);
    });

    test('Servo: Servo.h, a no-argument constructor, named parameters with their Dart defaults', () {
      final servo = classNamed('Servo');
      expect((servo.cppName, servo.header), ('Servo', 'Servo.h'));
      expect(servo.constructor, isEmpty);
      expect(servo.methods.map(signature), [
        'attach(pin: int32 as int [-32768..32767], min: int32 as int [33..1059] @CppRange named = 544, '
            'max: int32 as int [1889..2915] @CppRange named = 2400) -> int32 as uint8_t',
        'write(angle: int32 as int [-32768..32767]) -> void_',
        'writeMicroseconds(microseconds: int32 as int [-32768..32767]) -> void_',
        'read() -> int32 as int',
        'readMicroseconds() -> int32 as int',
        'attached() -> bool_ as bool',
        'detach() -> void_',
      ]);
    });
  });

  group("the user's file", () {
    late ApiBindings bindings;
    setUpAll(() async => bindings = reader.readLibrary(await resolve('''
import 'package:unodar/unodar.dart';

@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
final class SoftSerial {
  external SoftSerial(@CppType('uint8_t') int rx, @CppType('uint8_t') int tx);
  external void begin(@CppType('long') int baud);
  @CppName('write')
  @CppType('size_t')
  external int writeByte(@CppType('uint8_t') int value);
  @CppName('write')
  external int writeBytes(int value, {bool flush = false, double scale = 1.5, required Uint8 count});
}

@CppClass('ns::Sensor')
abstract final class Sensor {
  external double read();
}

@CppName('sensor0')
external final Sensor sensor;

final link = SoftSerial(10, 11);

void setup() {}

void loop() {}
''')));

    test('reads the class, its constructor, and @CppName overloads', () {
      final soft = bindings.classes.firstWhere((c) => c.dartName == 'SoftSerial');
      expect((soft.cppName, soft.header), ('SoftwareSerial', 'SoftwareSerial.h'));
      expect(soft.constructor!.map(describe), ['rx: int32 as uint8_t [0..255]', 'tx: int32 as uint8_t [0..255]']);
      expect(soft.methods.map(signature), [
        'begin(baud: int32 as long [-2147483648..2147483647]) -> void_',
        'write(value: int32 as uint8_t [0..255]) -> int32 as size_t',
        'write(value: int32 as int32_t [-2147483648..2147483647], flush: bool_ as bool named = false, '
            'scale: float32 as float named = 1.5, count: uint8 as uint8_t [0..255] named required) -> int32',
      ]);
      expect(soft.method('writeByte')!.cppName, 'write');
    });

    test('an int result without @CppType has no known C++ type; a double result is a float', () {
      final soft = bindings.classes.firstWhere((c) => c.dartName == 'SoftSerial');
      expect(soft.method('writeBytes')!.cppReturnType, isNull);
      final sensor = bindings.classes.firstWhere((c) => c.dartName == 'Sensor');
      expect((sensor.cppName, sensor.header, sensor.constructor), ('ns::Sensor', null, null));
      expect(signature(sensor.method('read')!), 'read() -> float32 as float');
    });

    test('external objects use @CppName; bound globals with a constructor are not objects', () {
      expect(bindings.objects.map((o) => (o.dartName, o.cppName, o.className)), [('sensor', 'sensor0', 'Sensor')]);
    });

    test('the registry takes the bindings, and refuses a name it already has', () {
      final registry = ApiRegistry.core().withBindings(bindings);
      final sensor = registry.object('sensor')!;
      expect(registry.classOf(sensor).cppName, 'ns::Sensor');
      expect(registry.classNamed('SoftSerial')!.method('begin')!.parameters.single.cppType, 'long');
      expect(registry.reservedNames, containsAll(['SoftSerial', 'SoftwareSerial', 'sensor', 'sensor0']));
      expect(() => registry.withBindings(bindings), throwsArgumentError);
    });
  });

  test('a class without @CppClass is not a binding', () async {
    final library = await resolve('''
import 'package:unodar/unodar.dart';

final class Plain {
  external void run();
}

external final Plain plain;

void setup() {}

void loop() {}
''');
    final bindings = reader.readLibrary(library);
    expect(bindings.classes, isEmpty);
    expect(bindings.objects, isEmpty);
  });

  test('an unsupported @CppType is a BindingError, never a guess (E017 rejects it first)', () async {
    final library = await resolve('''
import 'package:unodar/unodar.dart';

@CppClass('Thing')
abstract final class Thing {
  external void set(@CppType('int64_t') int value);
}

void setup() {}

void loop() {}
''');
    expect(() => reader.readLibrary(library), throwsA(isA<BindingError>()));
  });
}
