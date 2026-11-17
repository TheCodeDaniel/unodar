/// Pins that an external object takes (`@CppUsesPins`, and `Serial`'s 0/1) are taken only in a program that uses the
/// object. The rejections are negative goldens (`e022_serial_pins`, …); this file checks the programs that must still
/// compile, which a negative golden cannot show.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/compiler.dart';

import '../test_paths.dart';

void main() {
  final scratch = Directory(fromPackage('test', '.pin_owners_scratch'));
  setUpAll(() => scratch.createSync(recursive: true));
  tearDownAll(() => scratch.deleteSync(recursive: true));
  var count = 0;

  Future<CompileResult> compile(String dart) async {
    final dir = Directory(p.join(scratch.path, '${count++}'))..createSync();
    final file = File(p.join(dir.path, 'input.dart'))..writeAsStringSync(dart);
    return Compiler().compile(file.path);
  }

  void expectCompiles(CompileResult result) {
    if (result case CompileFailure(:final diagnostics)) {
      fail('expected success, got:\n${diagnostics.map((d) => d.format()).join('\n')}');
    }
    expect(result, isA<CompileSuccess>());
  }

  test('pins 0 and 1 are free in a program that does not use Serial', () async {
    expectCompiles(await compile('''
import 'package:unodar/unodar.dart';

final led = Led(pin: 1);
final button = Button(pin: 0, onPressed: () { led.toggle(); });

void main() => runDevice(Device(board: Uno(), children: [led, button]));
'''));
  });

  test('A4 and A5 are free in a program that does not use Wire', () async {
    expectCompiles(await compile('''
import 'package:unodar/unodar.dart';

final led = Led(pin: A4);
final button = Button(pin: A5, onPressed: () { led.toggle(); });

void main() => runDevice(Device(board: Uno(), children: [led, button]));
'''));
  });

  test('the DHT wrapper does not take pins 0 and 1: it links Serial but never opens it', () async {
    expectCompiles(await compile('''
import 'package:unodar/dht.dart';
import 'package:unodar/unodar.dart';

final sensor = Dht(2, DHT22);
final led = Led(pin: 1);
final button = Button(pin: 0, onPressed: () { led.set(sensor.read()); });

void main() => runDevice(Device(board: Uno(), children: [
      OnStart(() { sensor.begin(); }),
      led,
      button,
    ]));
'''));
  });
}
