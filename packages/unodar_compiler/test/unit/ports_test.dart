import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/toolchain/ports.dart';

import '../test_paths.dart';

/// Port choice for `unodar flash` (D6): automatic only for exactly one port identified as an Uno. The fixtures are
/// `arduino-cli board list --format json` output (arduino-cli 1.5.1's shape).
void main() {
  List<SerialPort> fixture(String name) =>
      parseBoardList(File(fromPackage('test', 'fixtures', 'board_list', '$name.json')).readAsStringSync());

  test('exactly one Uno is chosen; ports without a board are ignored', () {
    final choice = choosePort(fixture('one_uno'));
    expect(choice, isA<PortChosen>());
    expect((choice as PortChosen).address, '/dev/cu.usbmodem1101');
  });

  test('no board: nothing chosen, and the message says what to check', () {
    final choice = choosePort(fixture('none'));
    expect(choice, isA<NoBoardFound>());
    final message = portProblem(choice, command: 'unodar flash', os: 'macos');
    expect(message, startsWith('No Arduino Uno found.'));
    expect(message, contains('data USB cable'));
    expect(message, contains('CH340'));
  });

  test('two Unos: nothing chosen, both listed with a --port line', () {
    final choice = choosePort(fixture('two_unos'));
    expect(choice, isA<SeveralBoards>());
    expect(
        portProblem(choice, command: 'unodar flash', os: 'linux'),
        '2 Arduino Unos are plugged in, so unodar does not choose one. Pick one:\n'
        '  unodar flash --port /dev/ttyACM0\n'
        '  unodar flash --port /dev/ttyACM1');
  });

  test('a CH340 clone is named as a probable clone but never chosen', () {
    final ports = fixture('clone');
    expect(ports.single.cloneChip, 'CH340');
    final choice = choosePort(ports);
    expect(choice, isA<NoBoardFound>());
    expect((choice as NoBoardFound).clones.single.address, '/dev/cu.wchusbserial1410');
    expect(portProblem(choice, command: 'unodar flash', os: 'macos'),
        contains('  unodar flash --port /dev/cu.wchusbserial1410'));
  });

  test('another board (a Mega) is not an Uno, and network ports are left out', () {
    final ports = fixture('mega');
    expect(ports.map((p) => p.address), ['/dev/ttyACM0']);
    final choice = choosePort(ports);
    expect(choice, isA<NoBoardFound>());
    expect(portProblem(choice, command: 'unodar flash', os: 'linux'), contains('USB serial ports seen: /dev/ttyACM0.'));
  });
}
