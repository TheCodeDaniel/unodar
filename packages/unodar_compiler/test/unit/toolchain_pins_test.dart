import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/toolchain/manifests.dart';
import 'package:unodar_compiler/src/toolchain/pins.dart';

import '../test_paths.dart';

/// The compiler embeds the two toolchain manifests of `tool/` (`unodar setup` and `doctor` run from a pub cache, with
/// no checkout). The copies must be identical, and the parsed pins must be what CI installs.
void main() {
  String tool(String name) => File(fromPackage('..', '..', 'tool', name)).readAsStringSync();

  test('the embedded arduino_toolchain.txt is identical to tool/arduino_toolchain.txt', () {
    expect(arduinoToolchainManifest, tool('arduino_toolchain.txt'), reason: 'run tool/embed_runtime.sh');
  });

  test('the embedded arduino_libraries.txt is identical to tool/arduino_libraries.txt', () {
    expect(arduinoLibrariesManifest, tool('arduino_libraries.txt'), reason: 'run tool/embed_runtime.sh');
  });

  test('the pins parse', () {
    final pins = ToolchainPins.embedded;
    expect(pins.cliVersion, '1.5.1');
    expect(pins.core, (name: 'arduino:avr', version: '1.8.8'));
    expect(pins.libraries.map((l) => '${l.name}@${l.version}'), [
      'Servo@1.3.0',
      'LiquidCrystal@1.0.7',
      'DHT sensor library@1.4.7',
      'Adafruit Unified Sensor@1.1.15',
    ]);
    expect(pins.archiveFor(os: 'macos', arch: 'arm64'), 'arduino-cli_1.5.1_macOS_ARM64.tar.gz');
    expect(pins.archiveFor(os: 'linux', arch: 'x64'), 'arduino-cli_1.5.1_Linux_64bit.tar.gz');
    expect(pins.archiveFor(os: 'windows', arch: 'x64'), isNull, reason: 'Windows is untested in v0.7 (D2)');
    expect(pins.sha256['arduino-cli_1.5.1_macOS_ARM64.tar.gz'],
        'cb952e8c1621c95ef5f1d17831c945e3d0ec5973f89c557a7ec8feb9c4f7d4c9');
    expect(pins.downloadUrl('arduino-cli_1.5.1_Linux_64bit.tar.gz'),
        'https://github.com/arduino/arduino-cli/releases/download/v1.5.1/arduino-cli_1.5.1_Linux_64bit.tar.gz');
  });

  test('every archive line names this arduino-cli version and a 64-digit checksum', () {
    final pins = ToolchainPins.embedded;
    for (final MapEntry(key: archive, value: hex) in pins.sha256.entries) {
      expect(archive, startsWith('arduino-cli_${pins.cliVersion}_'));
      expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });

  test('CI installs the pinned arduino-cli and core', () {
    final ci = File(fromPackage('..', '..', '.github', 'workflows', 'ci.yml')).readAsStringSync();
    final pins = ToolchainPins.embedded;
    expect(ci, contains('ARDUINO_CLI_VERSION: ${pins.cliVersion}\n'));
    expect(ci, contains('ARDUINO_AVR_CORE: ${pins.core.name}@${pins.core.version}\n'));
  });

  test('a malformed line is an error, not ignored', () {
    expect(
        () => ToolchainPins.parse(toolchain: 'arduino-cli@1.5.1\nbogus line\n', libraries: ''), throwsFormatException);
    expect(() => ToolchainPins.parse(toolchain: 'core arduino:avr@1.8.8\n', libraries: ''), throwsFormatException,
        reason: 'no arduino-cli line');
  });
}
