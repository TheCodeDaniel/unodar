import 'dart:convert';

/// One port from `arduino-cli board list --format json`.
final class SerialPort {
  const SerialPort({required this.address, this.boards = const [], this.vid, this.pid});

  /// `/dev/cu.usbmodem1101`, `/dev/ttyACM0`, `COM3`.
  final String address;

  /// The FQBNs arduino-cli identified on it (`arduino:avr:uno`), from the USB id of genuine boards.
  final List<String> boards;

  /// The USB vendor and product id, lower-case hex without `0x` (`1a86`, `7523`), when the port is USB.
  final String? vid;
  final String? pid;

  /// The USB-serial chip of a typical Uno clone (arduino-cli cannot identify the board behind it), or null.
  String? get cloneChip => switch ('$vid:$pid') {
        '1a86:7523' => 'CH340',
        '1a86:5523' => 'CH341',
        '0403:6001' => 'FTDI FT232R',
        '10c4:ea60' => 'CP2102',
        _ => null,
      };
}

/// Reads the serial ports of `arduino-cli board list --format json` (other protocols, e.g. network, are left out).
List<SerialPort> parseBoardList(String json) {
  final decoded = jsonDecode(json) as Map<String, Object?>;
  return [
    for (final entry in (decoded['detected_ports'] as List<Object?>? ?? const []).cast<Map<String, Object?>>())
      if (entry['port'] case {'address': final String address, 'protocol': 'serial'} && final Map<String, Object?> port)
        SerialPort(
          address: address,
          boards: [
            for (final board in (entry['matching_boards'] as List<Object?>? ?? const []).cast<Map<String, Object?>>())
              if (board['fqbn'] case final String fqbn) fqbn,
          ],
          vid: _hex((port['properties'] as Map<String, Object?>?)?['vid']),
          pid: _hex((port['properties'] as Map<String, Object?>?)?['pid']),
        ),
  ];
}

String? _hex(Object? value) => value is String && value.isNotEmpty ? value.toLowerCase().replaceFirst('0x', '') : null;

/// Which port `unodar flash` uploads to (DECISIONS 2026-11-17, Phase 7 D6).
sealed class PortChoice {
  const PortChoice();
}

/// Exactly one port is identified as the board.
final class PortChosen extends PortChoice {
  const PortChosen(this.address);

  final String address;
}

/// No port is identified as the board. [clones] are USB-serial chips of typical clones, never chosen
/// automatically: writing to the wrong device (a GPS, a 3D printer) is worse than one more flag.
final class NoBoardFound extends PortChoice {
  const NoBoardFound({required this.clones, required this.others});

  final List<SerialPort> clones;

  /// Other USB serial ports (with a USB id), for the message.
  final List<SerialPort> others;
}

/// Several ports are identified as the board.
final class SeveralBoards extends PortChoice {
  const SeveralBoards(this.addresses);

  final List<String> addresses;
}

/// Chooses the port to upload to: only exactly one port identified as [fqbn].
PortChoice choosePort(List<SerialPort> ports, {String fqbn = 'arduino:avr:uno'}) {
  final boards = [
    for (final port in ports)
      if (port.boards.contains(fqbn)) port.address
  ];
  if (boards.length == 1) return PortChosen(boards.single);
  if (boards.length > 1) return SeveralBoards(boards);
  return NoBoardFound(
    clones: [
      for (final port in ports)
        if (port.cloneChip != null) port
    ],
    others: [
      for (final port in ports)
        if (port.cloneChip == null && port.vid != null) port
    ],
  );
}

/// The message for a [PortChoice] that is not [PortChosen], ending with what to run.
String portProblem(PortChoice choice, {required String command, required String os}) => switch (choice) {
      PortChosen() => '',
      SeveralBoards(:final addresses) => [
          '${addresses.length} Arduino Unos are plugged in, so unodar does not choose one. Pick one:',
          for (final address in addresses) '  $command --port $address',
        ].join('\n'),
      NoBoardFound(:final clones, :final others) => [
          if (clones.isNotEmpty) ...[
            'No port is identified as an Arduino Uno, but these look like the USB-serial chip of an Uno clone, '
                'which arduino-cli cannot identify:',
            for (final port in clones) '  ${port.address} (${port.cloneChip})',
            'If one of them is your board, upload to it with:',
            for (final port in clones) '  $command --port ${port.address}',
          ] else ...[
            'No Arduino Uno found.',
            if (others.isNotEmpty) 'USB serial ports seen: ${others.map((p) => p.address).join(', ')}.',
            'Check that:',
            '  - the board is plugged in with a data USB cable (some cables only charge);',
            if (os == 'macos')
              '  - for a clone with a CH340 chip on an older macOS, its driver is installed;'
            else if (os == 'linux')
              '  - you may open serial ports (`unodar doctor` checks the dialout group);',
            '  - no other program (a serial monitor, the Arduino IDE) holds the port.',
            'If you know the port, run `$command --port <port>`.',
          ],
        ].join('\n'),
    };
