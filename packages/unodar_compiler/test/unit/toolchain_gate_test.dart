import 'package:test/test.dart';

import '../arduino_toolchain.dart';

/// The `arduino` test gate names what is missing: the core, or any library of `tool/arduino_libraries.txt` (or a
/// different version of one), with the exact install commands.
void main() {
  const core = 'ID          Installed Latest Name\narduino:avr 1.8.8     1.8.8  Arduino AVR Boards\n';
  // Every library of the manifest, as `arduino-cli lib list` prints them.
  const installed = 'Name                    Installed Available Location Description\n'
      'Adafruit Unified Sensor 1.1.15    -         user     -\n'
      'DHT sensor library      1.4.7     -         user     -\n'
      'LiquidCrystal           1.0.7     -         user     -\n'
      'Servo                   1.3.0     -         user     -\n';

  test('the manifest lists Servo 1.3.0, LiquidCrystal 1.0.7, DHT sensor library 1.4.7 and its dependency', () {
    expect(arduinoLibraries, [
      (name: 'Servo', version: '1.3.0'),
      (name: 'LiquidCrystal', version: '1.0.7'),
      (name: 'DHT sensor library', version: '1.4.7'),
      (name: 'Adafruit Unified Sensor', version: '1.1.15'),
    ]);
  });

  test('ready when the core and every manifest library are installed', () {
    expect(missingFrom(coreList: core, libraryList: installed), isNull);
  });

  test('reports a missing core first', () {
    expect(missingFrom(coreList: 'No platforms installed.\n', libraryList: installed), contains('arduino:avr'));
  });

  test('reports a missing library or another version, and the install help names the exact version', () {
    expect(missingFrom(coreList: core, libraryList: 'No libraries installed.\n'), 'the Servo library is not installed');
    expect(missingFrom(coreList: core, libraryList: 'Servo 1.3.0 - user -\n'),
        'the LiquidCrystal library is not installed');
    expect(missingFrom(coreList: core, libraryList: 'ServoEasing 3.0.0 - user -\n'), isNotNull);
    expect(missingFrom(coreList: core, libraryList: 'Servo 1.2.2 - user -\n'),
        'the Servo library is 1.2.2, but unodar is tested with 1.3.0');
    expect(installHelp, contains('arduino-cli lib install --no-deps Servo@1.3.0'));
  });

  test('a library with a space in its name is quoted in the install help', () {
    expect(installCommand((name: 'DHT sensor library', version: '1.4.7')),
        'arduino-cli lib install --no-deps "DHT sensor library@1.4.7"');
  });

  group('every dependency is in the manifest (CI installs with --no-deps)', () {
    test('a library.properties depends= line is read, version constraints and all', () {
      expect(dependsOf('name=DHT sensor library\nversion=1.4.7\ndepends=Adafruit Unified Sensor\n'),
          ['Adafruit Unified Sensor']);
      expect(dependsOf('depends=A (>=1.0.0), B\n'), ['A', 'B']);
      expect(dependsOf('name=Servo\nversion=1.3.0\n'), isEmpty);
    });

    test('negative control: a dependency missing from the manifest is reported', () {
      const manifest = [(name: 'DHT sensor library', version: '1.4.7')];
      expect(
          undeclaredDependencies(manifest, {
            'DHT sensor library': ['Adafruit Unified Sensor']
          }),
          ['DHT sensor library depends on Adafruit Unified Sensor, which is not in tool/arduino_libraries.txt']);
      expect(
          undeclaredDependencies([
            ...manifest,
            (name: 'Adafruit Unified Sensor', version: '1.1.15')
          ], {
            'DHT sensor library': ['Adafruit Unified Sensor'],
            'Adafruit Unified Sensor': [],
          }),
          isEmpty);
    });
  });
}
