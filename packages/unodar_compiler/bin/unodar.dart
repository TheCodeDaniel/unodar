import 'dart:io';

import 'package:unodar_compiler/src/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  final code =
      await runCli(arguments, out: stdout, err: stderr, color: stderr.hasTerminal && stderr.supportsAnsiEscapes);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
