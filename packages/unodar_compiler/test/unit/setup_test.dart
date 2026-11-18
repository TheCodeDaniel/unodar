import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unodar_compiler/src/toolchain/pins.dart';
import 'package:unodar_compiler/src/toolchain/setup.dart';
import 'package:unodar_compiler/src/toolchain/toolchain.dart';

import '../fake_arduino_cli.dart';

/// `unodar setup` against a fake download and a fake arduino-cli: what it installs, that it does only what is
/// missing, and that it refuses a download with the wrong checksum. The real downloads run in the fresh-machine CI
/// job.
void main() {
  late Directory temp;
  late UnodarHome home;
  late FakeArduinoCli fake;
  late List<int> archive;
  late ToolchainPins pins;
  late List<Uri> fetched;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('unodar_setup_test_');
    home = UnodarHome(p.join(temp.path, 'home'));
    // The "real" arduino-cli behind the download: a fake with nothing installed yet.
    fake = FakeArduinoCli(p.join(temp.path, 'fake'), cores: const {}, libraries: const {});
    // The release archive holds a stub that forwards to the fake, so the fake's state lives outside the home folder.
    final stub = Directory(p.join(temp.path, 'archive'))..createSync();
    File(p.join(stub.path, 'arduino-cli')).writeAsStringSync('#!/bin/sh\nexec "${fake.executable}" "\$@"\n');
    File(p.join(stub.path, 'LICENSE.txt')).writeAsStringSync('license\n');
    final tarball = p.join(temp.path, 'arduino-cli.tar.gz');
    Process.runSync('tar', ['-czf', tarball, '-C', stub.path, 'arduino-cli', 'LICENSE.txt']);
    archive = File(tarball).readAsBytesSync();
    pins = ToolchainPins.parse(
      toolchain: 'arduino-cli@1.5.1\ncore arduino:avr@1.8.8\n'
          'sha256 arduino-cli_1.5.1_macOS_ARM64.tar.gz ${sha256.convert(archive)}\n',
      libraries: 'Servo@1.3.0\nDHT sensor library@1.4.7\n',
    );
    fetched = [];
    // What the core install would unpack: a runnable avr-gcc, which the final doctor check runs.
    final gcc = File(p.join(home.dataDirectory, 'packages', 'arduino', 'tools', 'avr-gcc', '7.3.0', 'bin', 'avr-gcc'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho "avr-gcc (GCC) 7.3.0"\n');
    Process.runSync('chmod', ['+x', gcc.path]);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<({int exitCode, String out, String err})> setup(
      {List<int>? download, String os = 'macos', String arch = 'arm64', bool dev = false}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runSetup(
      home: home,
      environment: {'PATH': p.join(temp.path, 'empty'), 'HOME': temp.path},
      out: out,
      err: err,
      dev: dev,
      pins: pins,
      os: os,
      arch: arch,
      fetch: (url) async {
        fetched.add(url);
        return download ?? archive;
      },
    );
    return (exitCode: code, out: '$out', err: '$err');
  }

  /// The fake's calls without the managed `--config-file` suffix (checked separately).
  List<String> calls() => [for (final c in fake.calls) c.replaceAll(' --config-file ${home.configFile}', '')];

  test('a fresh install downloads, verifies and installs everything, exit 0', () async {
    final r = await setup();
    expect(r.exitCode, 0, reason: '${r.out}\n${r.err}');
    expect(fetched, [
      Uri.parse('https://github.com/arduino/arduino-cli/releases/download/v1.5.1/arduino-cli_1.5.1_macOS_ARM64.tar.gz')
    ]);
    expect(File(home.cli).existsSync(), isTrue);
    expect(File(home.configFile).readAsStringSync(), home.configYaml);
    expect(r.out, contains('✓ arduino-cli 1.5.1 (checksum verified)'));
    final installs = calls().where((c) => c.contains('install') || c.contains('update-index')).toList();
    expect(installs, [
      'core update-index',
      'core install arduino:avr@1.8.8',
      'lib update-index',
      'lib install --no-deps Servo@1.3.0',
      'lib install --no-deps DHT sensor library@1.4.7',
    ]);
    expect(fake.calls, everyElement(endsWith('--config-file ${home.configFile}')),
        reason: 'the managed copy must never fall back to ~/.arduino15');
    expect(r.out, endsWith('Ready.\n'));
  });

  test('a second run downloads and installs nothing', () async {
    await setup();
    final before = calls().length;
    fetched.clear();
    final r = await setup();
    expect(r.exitCode, 0, reason: r.out);
    expect(fetched, isEmpty);
    expect(calls().skip(before).where((c) => c.contains('install') || c.contains('update-index')), isEmpty);
    expect(r.out, contains('✓ arduino-cli 1.5.1 (already installed)'));
    expect(r.out, contains('✓ core arduino:avr 1.8.8 (already installed)'));
  });

  test('only a missing library is installed', () async {
    await setup();
    File(p.join(fake.dir, 'libs.txt')).writeAsStringSync('Servo\t1.3.0\n');
    final before = calls().length;
    final r = await setup();
    expect(r.exitCode, 0, reason: r.out);
    expect(
        calls().skip(before).where((c) => c.contains('install')), ['lib install --no-deps DHT sensor library@1.4.7']);
  });

  test('negative control: a download with the wrong checksum is refused and nothing is installed, exit 3', () async {
    final r = await setup(download: [...archive, 0]);
    expect(r.exitCode, 3);
    expect(r.err, contains('has the wrong SHA-256'));
    expect(File(home.cli).existsSync(), isFalse);
    expect(fake.calls, isEmpty);
  });

  test('a failed download is exit 3 with the retry advice', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runSetup(
        home: home,
        environment: const {},
        out: out,
        err: err,
        pins: pins,
        os: 'macos',
        arch: 'arm64',
        fetch: (_) async => throw const SocketException('no network'));
    expect(code, 3);
    expect('$err', contains('could not download'));
    expect('$err', contains('run `unodar setup` again'));
  });

  test('a platform without an archive (Windows) is exit 3 with what to do instead', () async {
    final r = await setup(os: 'windows', arch: 'x64');
    expect(r.exitCode, 3);
    expect(r.err, contains('no arduino-cli download for windows_x64 (Windows is untested in this version)'));
    expect(fetched, isEmpty);
  });

  test('a failing arduino-cli step stops the setup with its error, exit 3', () async {
    FakeArduinoCli(fake.dir, cores: const {}, libraries: const {}, failing: {'core': 1});
    final r = await setup();
    expect(r.exitCode, 3);
    expect(r.err, contains('fake failure of core'));
  });

  test('--dev outside a checkout is a usage error, exit 2', () async {
    final r = await setup(dev: true);
    expect(r.exitCode, 2);
    expect(r.err, contains('inside your clone'));
  });
}
