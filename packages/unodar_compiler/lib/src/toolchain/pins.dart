import 'dart:convert';

import 'manifests.dart';

/// One Arduino library at an exact version, as `tool/arduino_libraries.txt` lists it. The name may contain spaces.
typedef PinnedLibrary = ({String name, String version});

/// The exact toolchain unodar is built and tested with (`tool/arduino_toolchain.txt`, `tool/arduino_libraries.txt`,
/// embedded in the compiler). `unodar setup` installs it and `unodar doctor` checks it.
final class ToolchainPins {
  const ToolchainPins._({required this.cliVersion, required this.core, required this.sha256, required this.libraries});

  /// The pins embedded in this compiler.
  static final ToolchainPins embedded =
      ToolchainPins.parse(toolchain: arduinoToolchainManifest, libraries: arduinoLibrariesManifest);

  /// Parses the two manifests. A line that is not a comment, blank, or one of the known forms is a
  /// [FormatException]: a pin that is silently skipped would install the wrong toolchain.
  factory ToolchainPins.parse({required String toolchain, required String libraries}) {
    String? cli;
    ({String name, String version})? core;
    final sha256 = <String, String>{};
    for (final line in _lines(toolchain)) {
      final words = line.split(RegExp(r'\s+'));
      if (words.length == 1 && line.startsWith('arduino-cli@')) {
        cli = line.substring('arduino-cli@'.length);
      } else if (words.length == 2 && words[0] == 'core' && words[1].contains('@')) {
        core = _spec(words[1]);
      } else if (words.length == 3 && words[0] == 'sha256' && RegExp(r'^[0-9a-f]{64}$').hasMatch(words[2])) {
        sha256[words[1]] = words[2];
      } else {
        throw FormatException('unreadable line in arduino_toolchain.txt: $line');
      }
    }
    if (cli == null || core == null) throw const FormatException('arduino_toolchain.txt needs arduino-cli@ and core');
    return ToolchainPins._(
      cliVersion: cli,
      core: core,
      sha256: sha256,
      libraries: [
        for (final line in _lines(libraries))
          if (line.contains('@')) _spec(line) else throw FormatException('unreadable library line: $line'),
      ],
    );
  }

  /// The arduino-cli version, e.g. `1.5.1`.
  final String cliVersion;

  /// The board core, e.g. `arduino:avr` at `1.8.8`.
  final ({String name, String version}) core;

  /// SHA-256 (lower-case hex) of each arduino-cli release archive setup may download, by file name.
  final Map<String, String> sha256;

  /// The libraries from the library index, each installed with `--no-deps` (every dependency is listed).
  final List<PinnedLibrary> libraries;

  /// The arduino-cli archive for [os] (`macos`, `linux`, as `Platform.operatingSystem`) and [arch] (`x64`, `arm64`),
  /// or null where unodar has none (Windows is untested in v0.7).
  String? archiveFor({required String os, required String arch}) {
    final name = switch ((os, arch)) {
      ('macos', 'x64') => 'macOS_64bit',
      ('macos', 'arm64') => 'macOS_ARM64',
      ('linux', 'x64') => 'Linux_64bit',
      ('linux', 'arm64') => 'Linux_ARM64',
      _ => null,
    };
    final archive = name == null ? null : 'arduino-cli_${cliVersion}_$name.tar.gz';
    return sha256.containsKey(archive) ? archive : null;
  }

  /// Where [archive] is downloaded from: the arduino-cli release on GitHub.
  String downloadUrl(String archive) =>
      'https://github.com/arduino/arduino-cli/releases/download/v$cliVersion/$archive';

  static Iterable<String> _lines(String text) =>
      LineSplitter.split(text).map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('#'));

  static ({String name, String version}) _spec(String spec) {
    final at = spec.lastIndexOf('@');
    return (name: spec.substring(0, at).trim(), version: spec.substring(at + 1).trim());
  }
}
