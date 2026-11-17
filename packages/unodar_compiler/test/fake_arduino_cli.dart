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
      Map<String, Object?>? compileResult,
      Map<String, int> failing = const {}}) {
    Directory(dir).createSync(recursive: true);
    _write('version.json', {'Application': 'arduino-cli', 'VersionString': version});
    File(p.join(dir, 'cores.txt'))
        .writeAsStringSync([for (final MapEntry(:key, :value) in cores.entries) '$key\t$value\n'].join());
    File(p.join(dir, 'libs.txt'))
        .writeAsStringSync([for (final MapEntry(:key, :value) in libraries.entries) '$key\t$value\n'].join());
    _write('board.json', {'detected_ports': ports});
    _write('compile.json', compileResult ?? successfulCompile);
    final fail = [
      for (final MapEntry(:key, :value) in failing.entries) '  "$key") echo "fake failure of $key" >&2; exit $value ;;',
    ].join('\n');
    File(executable).writeAsStringSync(_script.replaceFirst('__FAIL__', fail));
    Process.runSync('chmod', ['+x', executable]);
  }

  final String dir;

  /// What `compile` prints by default: blink's sizes.
  static const successfulCompile = {
    'success': true,
    'compiler_out': '',
    'compiler_err': '',
    'builder_result': {
      'executable_sections_size': [
        {'name': 'text', 'size': 924, 'max_size': 32256},
        {'name': 'data', 'size': 9, 'max_size': 2048},
      ]
    },
  };

  String get executable => p.join(dir, 'arduino-cli');

  /// Every call so far, one line of arguments each.
  List<String> get calls {
    final log = File(p.join(dir, 'calls.log'));
    return log.existsSync() ? log.readAsLinesSync() : const [];
  }

  void _write(String name, Object json) => File(p.join(dir, name)).writeAsStringSync(jsonEncode(json));
}

/// The fake's shell script. `__FAIL__` becomes the `case` arms of the commands told to fail. Installed cores and
/// libraries are tab-separated `name<TAB>version` lines in `cores.txt`/`libs.txt`; an install replaces a name's line.
const _script = r'''#!/bin/sh
# Fake arduino-cli for unodar's tests.
here="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$here/calls.log"
case "$1" in
__FAIL__
esac
json() { awk -F'\t' -v key="$1" -v ver="$2" -v wrap="$3" 'BEGIN { printf "{\"%s\":[", wrap }
  NF == 2 { if (n++) printf ","; if (wrap == "platforms") printf "{\"%s\":\"%s\",\"%s\":\"%s\"}", key, $1, ver, $2;
            else printf "{\"library\":{\"%s\":\"%s\",\"%s\":\"%s\"}}", key, $1, ver, $2 }
  END { print "]}" }' "$4"; }
replace() { grep -v "^$2	" "$1" > "$1.tmp" || true; printf '%s\t%s\n' "$2" "$3" >> "$1.tmp"; mv "$1.tmp" "$1"; }
case "$1 $2" in
  "version "*) cat "$here/version.json" ;;
  "core list") json id installed_version platforms "$here/cores.txt" ;;
  "lib list") json name version installed_libraries "$here/libs.txt" ;;
  "board list") cat "$here/board.json" ;;
  "core install") spec="$3"; replace "$here/cores.txt" "${spec%@*}" "${spec##*@}" ;;
  "lib install") spec="$4"; replace "$here/libs.txt" "${spec%@*}" "${spec##*@}" ;;
  "config get") echo "$here/data" ;;
  "compile "*) cat "$here/compile.json"; grep -q '"success":true' "$here/compile.json" || exit 1 ;;
  *) echo "{}" ;;
esac
''';
