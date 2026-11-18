import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/toolchain/toolchain.dart';

import '../fake_arduino_cli.dart';

void main() {
  late Directory temp;
  late UnodarHome home;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('unodar_toolchain_test_');
    home = UnodarHome(p.join(temp.path, 'home'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// A fake arduino-cli installed as the managed copy in [home].
  FakeArduinoCli managed({String version = '1.5.1', Map<String, String>? libraries}) => libraries == null
      ? FakeArduinoCli(p.dirname(home.cli), version: version)
      : FakeArduinoCli(p.dirname(home.cli), version: version, libraries: libraries);

  /// A fake arduino-cli in a PATH directory of its own.
  ({FakeArduinoCli cli, Map<String, String> env}) onPath({Map<String, String> cores = const {'arduino:avr': '1.8.8'}}) {
    final cli = FakeArduinoCli(p.join(temp.path, 'path'), version: '1.4.0', cores: cores);
    return (cli: cli, env: {'PATH': cli.dir});
  }

  test('UNODAR_HOME overrides ~/.unodar', () {
    expect(UnodarHome.fromEnvironment({'HOME': '/u', 'UNODAR_HOME': '/x/y'}).path, '/x/y');
    expect(UnodarHome.fromEnvironment({'HOME': '/u'}).path, '/u/.unodar');
  });

  test('the managed configuration keeps everything inside the home folder', () {
    expect(home.configYaml, contains('data: ${home.path}/data\n'));
    expect(home.configYaml, contains('user: ${home.path}/user\n'));
    expect(home.configYaml, contains('downloads: ${home.path}/downloads\n'));
  });

  test('the managed copy is found first, and called with its config file', () {
    final fake = managed();
    final path = onPath();
    final found = locateToolchain(home: home, environment: path.env);
    expect(found, isA<ToolchainFound>());
    final cli = (found as ToolchainFound).cli;
    expect(cli.managed, isTrue);
    expect(cli.executable, home.cli);
    expect(fake.calls, everyElement(endsWith('--config-file ${home.configFile}')));
    expect(path.cli.calls, isEmpty);
  });

  test('a managed copy of another arduino-cli version is not used', () {
    managed(version: '1.4.0');
    final result = locateToolchain(home: home, environment: const {});
    expect(result, isA<ToolchainNotFound>());
    expect((result as ToolchainNotFound).message,
        contains('the managed arduino-cli (${home.path}): arduino-cli is 1.4.0, but unodar is tested with 1.5.1'));
    expect(result.message, contains('Run `unodar setup`'));
  });

  test('without a managed copy, arduino-cli on PATH is used when it has the pinned core and libraries', () {
    final path = onPath();
    final found = locateToolchain(home: home, environment: path.env);
    expect(found, isA<ToolchainFound>());
    expect((found as ToolchainFound).cli.managed, isFalse);
    expect(found.inventory.cliVersion, '1.4.0', reason: 'its own version is reported, not required');
    expect(path.cli.calls, everyElement(isNot(contains('--config-file'))));
  });

  test('arduino-cli on PATH with another core version is not used, and the message says why', () {
    final path = onPath(cores: {'arduino:avr': '1.8.6'});
    final result = locateToolchain(home: home, environment: path.env) as ToolchainNotFound;
    expect(result.reasons, [
      'no managed toolchain in ${home.path}',
      'arduino-cli on PATH (${path.cli.executable}): the arduino:avr core is 1.8.6, but unodar is tested with 1.8.8',
    ]);
  });

  test('a missing library is named', () {
    managed(libraries: {'Servo': '1.3.0'});
    final result = locateToolchain(home: home, environment: const {}) as ToolchainNotFound;
    expect(result.reasons.first, contains('the library LiquidCrystal is not installed'));
    expect(result.reasons.first, contains('the library Adafruit Unified Sensor is not installed'));
  });

  test('nothing at all', () {
    final result = locateToolchain(home: home, environment: {'PATH': p.join(temp.path, 'empty')}) as ToolchainNotFound;
    expect(result.reasons, ['no managed toolchain in ${home.path}', 'no arduino-cli on PATH']);
  });

  test('an arduino-cli that fails is reported, not a crash', () {
    FakeArduinoCli(p.dirname(home.cli), failing: {'version': 3});
    final result = locateToolchain(home: home, environment: const {}) as ToolchainNotFound;
    expect(result.reasons.first, contains('`arduino-cli version` failed: fake failure of version'));
  });

  test('an executable that cannot run is reported', () {
    File(home.cli)
      ..createSync(recursive: true)
      ..writeAsStringSync('not a program');
    final result = locateToolchain(home: home, environment: const {}) as ToolchainNotFound;
    expect(result.reasons.first, contains('cannot be run'));
  }, testOn: '!windows');
}
