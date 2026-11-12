import 'package:test/test.dart';

import '../arduino_toolchain.dart';

/// The `arduino` test gate names what is missing, including the Servo library, which is not part of the core.
void main() {
  const core = 'ID          Installed Latest Name\narduino:avr 1.8.8     1.8.8  Arduino AVR Boards\n';
  const servo = 'Name  Installed Available Location Description\nServo 1.3.0     -         user     -\n';

  test('ready when the core and Servo are installed', () {
    expect(missingFrom(coreList: core, libraryList: servo), isNull);
  });

  test('reports a missing core first', () {
    expect(missingFrom(coreList: 'No platforms installed.\n', libraryList: servo), contains('arduino:avr'));
  });

  test('reports a missing Servo library, and the install help names it', () {
    expect(missingFrom(coreList: core, libraryList: 'No libraries installed.\n'), 'the Servo library is not installed');
    expect(missingFrom(coreList: core, libraryList: 'ServoEasing 3.0.0 - user -\n'), isNotNull);
    expect(installHelp, contains('arduino-cli lib install Servo@1.3.0'));
  });
}
