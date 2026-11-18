import 'package:test/test.dart';

import '../arduino_toolchain.dart';

/// The `arduino` test gate's install help and dependency check. What is missing is found by `locateToolchain`,
/// tested in `toolchain_test.dart`.
void main() {
  test('the manifest lists Servo 1.3.0, LiquidCrystal 1.0.7, DHT sensor library 1.4.7 and its dependency', () {
    expect(arduinoLibraries, [
      (name: 'Servo', version: '1.3.0'),
      (name: 'LiquidCrystal', version: '1.0.7'),
      (name: 'DHT sensor library', version: '1.4.7'),
      (name: 'Adafruit Unified Sensor', version: '1.1.15'),
    ]);
  });

  test('the install help names the exact version', () {
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
