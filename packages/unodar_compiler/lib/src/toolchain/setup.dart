import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'doctor.dart';
import 'pins.dart';
import 'toolchain.dart';

/// Downloads [url] and returns its bytes (injectable so that tests never touch the network).
typedef Fetch = Future<List<int>> Function(Uri url);

/// Thrown by a step of [runSetup] that cannot continue; [exitCode] is 3 (toolchain) or 2 (usage).
final class SetupException implements Exception {
  const SetupException(this.message, {this.exitCode = 3});

  final String message;
  final int exitCode;
}

/// `unodar setup` (PRD §8.1): installs the pinned arduino-cli, core and libraries into [home], doing only the steps
/// whose check fails, so it is safe to re-run. Nothing outside [home] is written. [dev] also installs the avr8js
/// runner of the tests in [checkout] (`npm ci`; Node itself is the user's). Returns the exit code: 0 when the doctor
/// finds nothing left to fix, else 3 (or 2 for `--dev` outside a checkout).
Future<int> runSetup({
  required UnodarHome home,
  required Map<String, String> environment,
  required StringSink out,
  required StringSink err,
  bool dev = false,
  String? checkout,
  ToolchainPins? pins,
  Fetch? fetch,
  String? os,
  String? arch,
}) async {
  pins ??= ToolchainPins.embedded;
  try {
    if (dev && checkout == null) {
      throw const SetupException(
          '--dev installs what the tests of a unodar checkout need, so run it inside your clone of the repository.',
          exitCode: 2);
    }
    out.writeln('Installing the Arduino toolchain unodar is tested with into ${home.path}.');
    out.writeln('Nothing outside that folder changes; `rm -rf ${home.path}` removes it all again.');
    for (final dir in [p.dirname(home.cli), home.dataDirectory, home.userDirectory, home.downloadsDirectory]) {
      Directory(dir).createSync(recursive: true);
    }
    final config = File(home.configFile);
    if (!config.existsSync() || config.readAsStringSync() != home.configYaml) config.writeAsStringSync(home.configYaml);

    await _installCli(
        home, pins, out, fetch ?? httpFetch(environment, out), os ?? Platform.operatingSystem, arch ?? _arch());
    final cli = ArduinoCli(home.cli, configFile: home.configFile, managed: true);
    var inventory = _inventory(cli);

    if (inventory.cores[pins.core.name] == pins.core.version) {
      out.writeln('✓ core ${pins.core.name} ${pins.core.version} (already installed)');
    } else {
      out.writeln('Installing the core ${pins.core.name} ${pins.core.version} and its compiler (the largest download, '
          'once)...');
      await _stream(cli, ['core', 'update-index'], out);
      await _stream(cli, ['core', 'install', '${pins.core.name}@${pins.core.version}'], out);
    }

    final libraries = [
      for (final l in pins.libraries)
        if (inventory.libraries[l.name] != l.version) l
    ];
    if (libraries.isEmpty) {
      out.writeln('✓ libraries ${pins.libraries.map((l) => '${l.name} ${l.version}').join(', ')} (already installed)');
    } else {
      await _stream(cli, ['lib', 'update-index'], out);
      for (final library in libraries) {
        out.writeln('Installing the library ${library.name} ${library.version}...');
        // --no-deps: every dependency is pinned in the manifest itself, so nothing floats (as in CI).
        await _stream(cli, ['lib', 'install', '--no-deps', '${library.name}@${library.version}'], out);
      }
    }
    inventory = _inventory(cli);

    if (dev) await _installRunner(checkout!, out);

    final checks = runDoctor(home: home, environment: environment, dev: dev, checkout: checkout, pins: pins);
    out
      ..writeln()
      ..writeln(renderDoctor(checks));
    return checks.any((c) => c.status == CheckStatus.problem) ? 3 : 0;
  } on SetupException catch (e) {
    err.writeln('error: ${e.message}');
    return e.exitCode;
  }
}

Future<void> _installCli(
    UnodarHome home, ToolchainPins pins, StringSink out, Fetch fetch, String os, String arch) async {
  final existing = managedCli(home);
  if (existing != null) {
    try {
      final version = ToolchainInventory.read(existing).cliVersion;
      if (version == pins.cliVersion) {
        out.writeln('✓ arduino-cli ${pins.cliVersion} (already installed)');
        return;
      }
      out.writeln('Replacing arduino-cli $version with ${pins.cliVersion}...');
    } on ToolchainException {
      out.writeln('The arduino-cli in ${home.path} does not run; installing it again...');
    }
  }
  final archive = pins.archiveFor(os: os, arch: arch);
  if (archive == null) {
    throw SetupException('unodar setup has no arduino-cli download for ${os}_$arch (Windows is untested in this '
        'version). Install arduino-cli yourself (https://arduino.github.io/arduino-cli/latest/installation/) with the '
        'core and libraries that `unodar doctor` lists; unodar then uses the one on PATH.');
  }
  final url = Uri.parse(pins.downloadUrl(archive));
  out.writeln('Downloading arduino-cli ${pins.cliVersion} from $url...');
  final List<int> bytes;
  try {
    bytes = await fetch(url);
  } on Object catch (e) {
    throw SetupException(setupErrorFor(e, url));
  }
  final actual = '${sha256.convert(bytes)}';
  if (actual != pins.sha256[archive]) {
    throw SetupException('the download of $archive has the wrong SHA-256 ($actual, expected '
        '${pins.sha256[archive]}), so it was not installed. Run `unodar setup` again; if this repeats, report it.');
  }
  final saved = File(p.join(home.downloadsDirectory, archive))..writeAsBytesSync(bytes);
  final unpack = Directory(p.join(home.downloadsDirectory, 'arduino-cli-${pins.cliVersion}'));
  if (unpack.existsSync()) unpack.deleteSync(recursive: true);
  unpack.createSync(recursive: true);
  final tar = Process.runSync('tar', ['-xzf', saved.path, '-C', unpack.path]);
  final unpacked = File(p.join(unpack.path, 'arduino-cli'));
  if (tar.exitCode != 0 || !unpacked.existsSync()) {
    throw SetupException('could not unpack $archive: ${'${tar.stderr}'.trim()}');
  }
  unpacked.copySync(home.cli);
  Process.runSync('chmod', ['755', home.cli]);
  unpack.deleteSync(recursive: true);
  saved.deleteSync();
  out.writeln('✓ arduino-cli ${pins.cliVersion} (checksum verified)');
}

ToolchainInventory _inventory(ArduinoCli cli) {
  try {
    return ToolchainInventory.read(cli);
  } on ToolchainException catch (e) {
    throw SetupException(e.message);
  }
}

/// Runs [args] with its output passed through line by line (arduino-cli prints download progress), and fails the
/// setup with the command's own error when it fails.
Future<void> _stream(ArduinoCli cli, List<String> args, StringSink out) async {
  final process = await Process.start(cli.executable, cli.arguments(args));
  final errors = StringBuffer();
  await Future.wait([
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach((l) => out.writeln('  $l')),
    process.stderr.transform(utf8.decoder).forEach(errors.write),
  ]);
  final code = await process.exitCode;
  if (code != 0) {
    throw SetupException('`arduino-cli ${args.join(' ')}` failed (exit $code): ${'$errors'.trim()}\n'
        'Check your connection (or HTTPS_PROXY) and run `unodar setup` again.');
  }
}

/// `npm ci` in `tool/avr_runner` unless it is already installed from the lockfile. Node itself is not installed.
Future<void> _installRunner(String checkout, StringSink out) async {
  if (avrRunnerInstalled(checkout)) {
    out.writeln('✓ tool/avr_runner (already installed)');
    return;
  }
  if (nodeVersion() == null) {
    throw const SetupException('the runtime tests need Node.js 20.19 or later, which unodar does not install: '
        '`brew install node` (or https://nodejs.org/), then run `unodar setup --dev` again.');
  }
  out.writeln('Installing the avr8js runner (npm ci in tool/avr_runner)...');
  final run = await Process.run('npm', ['ci', '--no-audit', '--no-fund'],
      workingDirectory: p.join(checkout, 'tool', 'avr_runner'), runInShell: Platform.isWindows);
  if (run.exitCode != 0) throw SetupException('npm ci failed in tool/avr_runner:\n${run.stderr}');
}

/// The message for a download of [url] that failed with [error].
String setupErrorFor(Object error, Uri url) {
  final reason = error is TimeoutException ? 'no data arrived for ${error.duration?.inSeconds ?? '?'} s' : '$error';
  return 'could not download $url: $reason.\nCheck your connection (or HTTPS_PROXY) and run `unodar setup` again; '
      'it continues where it stopped.';
}

/// The real download: follows redirects (GitHub release assets redirect), honours `HTTPS_PROXY`, prints progress
/// to [out] every [progressEvery] bytes, and gives up with a [TimeoutException] when no data arrives for
/// [idleTimeout] (a stalled connection would otherwise hang `setup` silently, as on a slow link in the
/// fresh-machine test).
Fetch httpFetch(Map<String, String> environment, StringSink out,
        {Duration idleTimeout = const Duration(seconds: 60), int progressEvery = 2 * 1024 * 1024}) =>
    (url) async {
      final client = HttpClient()
        ..connectionTimeout = idleTimeout
        ..findProxy = (uri) => HttpClient.findProxyFromEnvironment(uri, environment: environment);
      try {
        final response = await (await client.getUrl(url)).close().timeout(idleTimeout);
        if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: url);
        final total = response.contentLength;
        String mb(int bytes) => (bytes / 1e6).toStringAsFixed(1);
        final bytes = <int>[];
        var reported = 0;
        await for (final chunk in response.timeout(idleTimeout, onTimeout: (sink) {
          sink.addError(TimeoutException('no data', idleTimeout));
          sink.close();
        })) {
          bytes.addAll(chunk);
          if (bytes.length - reported >= progressEvery || (total > 0 && bytes.length == total)) {
            reported = bytes.length;
            out.writeln('  ${mb(bytes.length)} MB${total > 0 ? ' of ${mb(total)} MB' : ''}');
          }
        }
        if (total > 0 && bytes.length != total) throw HttpException('the connection closed early', uri: url);
        return bytes;
      } finally {
        client.close(force: true);
      }
    };

String _arch() {
  final platform = platformName();
  return platform.endsWith('arm64') ? 'arm64' : (platform.endsWith('x64') ? 'x64' : platform.split('_').last);
}
