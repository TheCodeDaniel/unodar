/// A stand-in `arduino-cli` for tests of the toolchain code (resolver, doctor, setup, flash): a shell script that
/// prints canned JSON for `version`, `core list`, `lib list` and `board list`, logs every call, and can be told to
/// fail. It never touches the network or a real board.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final class FakeArduinoCli {
  /// Writes the script to `<dir>/arduino-cli` and its data next to it.
  FakeArduinoCli(this.dir,
      {String version = '1.5.1',
      Map<String, String> cores = const {'arduino:avr': '1.8.8'},
      Map<String, String> libraries = const {
        'Servo': '1.3.0',
        'LiquidCrystal': '1.0.7',
        'DHT sensor library': '1.4.7',
        'Adafruit Unified Sensor': '1.1.15',
      },
      List<Map<String, Object?>> ports = const [],
      Map<String, int> failing = const {}}) {
    Directory(dir).createSync(recursive: true);
    _write('version.json', {'Application': 'arduino-cli', 'VersionString': version});
    _write('core.json', {
      'platforms': [
        for (final MapEntry(:key, :value) in cores.entries) {'id': key, 'installed_version': value},
      ]
    });
    _write('lib.json', {
      'installed_libraries': [
        for (final MapEntry(:key, :value) in libraries.entries)
          {
            'library': {'name': key, 'version': value}
          },
      ]
    });
    _write('board.json', {'detected_ports': ports});
    final fail = [
      for (final MapEntry(:key, :value) in failing.entries) '  "$key") echo "fake failure of $key" >&2; exit $value ;;',
    ].join('\n');
    File(executable).writeAsStringSync('''
#!/bin/sh
# Fake arduino-cli for unodar's tests.
here="\$(cd "\$(dirname "\$0")" && pwd)"
printf '%s\\n' "\$*" >> "\$here/calls.log"
case "\$1" in
$fail
esac
case "\$1 \$2" in
  "version "*) cat "\$here/version.json" ;;
  "core list") cat "\$here/core.json" ;;
  "lib list") cat "\$here/lib.json" ;;
  "board list") cat "\$here/board.json" ;;
  *) echo "{}" ;;
esac
''');
    Process.runSync('chmod', ['+x', executable]);
  }

  final String dir;

  String get executable => p.join(dir, 'arduino-cli');

  /// Every call so far, one line of arguments each.
  List<String> get calls {
    final log = File(p.join(dir, 'calls.log'));
    return log.existsSync() ? log.readAsLinesSync() : const [];
  }

  void _write(String name, Object json) => File(p.join(dir, name)).writeAsStringSync(jsonEncode(json));
}
