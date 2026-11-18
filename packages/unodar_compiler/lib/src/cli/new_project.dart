import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../version.dart';

/// The repository `unodar new` points a project's `package:unodar` at (D1: git url, path and the release tag).
const unodarRepository = 'https://github.com/TheCodeDaniel/unodar';

/// The release tag of this compiler's version, which a new project depends on.
String get releaseTag => 'v$unodarVersion';

/// `main.dart` of a new project. `test/golden/new_project/input.dart` is a verbatim copy (compiled, budgeted and run
/// in avr8js); a test keeps them equal.
const newProjectMain = '''
import 'package:unodar/unodar.dart';

// The LED on the board (pin 13, marked L) blinks: on for half a second, off for half a second. Nothing to wire.
// Plug the Uno in and run `unodar flash`. Then try a button: see the README of this project.
final led = Led(pin: LED_BUILTIN);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Every(Duration(milliseconds: 500), () {
            led.toggle();
          }),
        ],
      ),
    );
''';

/// The `pubspec.yaml` of a new project named [name]: `package:unodar` from the release tag of this compiler, or from
/// [unodarPath] (a checkout's `packages/unodar`, for contributors and tests).
String newProjectPubspec(String name, {String? unodarPath}) => '''
name: $name
description: An Arduino program written in Dart with unodar.
publish_to: none

environment:
  sdk: ^3.6.0

dependencies:
${unodarPath == null ? '''  # The unodar API, at exactly the version of the unodar compiler (unodar $unodarVersion).
  # Upgrade both together.
  unodar:
    git:
      url: $unodarRepository
      path: packages/unodar
      ref: $releaseTag''' : '''  unodar:
    path: ${jsonEncode(unodarPath)}'''}
''';

String newProjectReadme(String name) => '''
# $name

An Arduino Uno program written in Dart with [unodar]($unodarRepository) (experimental).

```sh
unodar flash      # build main.dart and upload it to the Uno plugged in
unodar build      # only build it, and print the flash and RAM it needs
unodar doctor     # check the toolchain if something does not work
```

`main.dart` blinks the LED on the board. Next, add a button between pin 2 and GND and let it toggle the LED:

```dart
final button = Button(pin: 2, onPressed: () { led.toggle(); });
```

and list `button` in `children`. What you can write is in the subset guide:
$unodarRepository/blob/$releaseTag/docs/SUBSET.md
''';

const newProjectGitignore = '''
# unodar build output (the generated C++ and arduino-cli's build folder)
build/
# Dart
.dart_tool/
''';

/// Whether [name] can be a Dart package name (and so the project's name).
bool isPackageName(String name) => RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name) && !_reservedWords.contains(name);

const _reservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default', 'do', 'else', 'enum', 'extends', //
  'false', 'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', //
  'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with', 'unodar',
};

/// Writes a new project into [directory] (which must not exist or be empty); returns the files written.
List<String> writeNewProject(String directory, {String? unodarPath}) {
  final name = p.basename(directory);
  final files = {
    'pubspec.yaml': newProjectPubspec(name, unodarPath: unodarPath),
    'main.dart': newProjectMain,
    'README.md': newProjectReadme(name),
    '.gitignore': newProjectGitignore,
  };
  Directory(directory).createSync(recursive: true);
  for (final MapEntry(key: file, value: text) in files.entries) {
    File(p.join(directory, file)).writeAsStringSync(text);
  }
  return files.keys.toList();
}
