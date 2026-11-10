import 'dart:io';

import 'package:unodar_compiler/src/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await runCli(arguments, out: stdout, err: stderr);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
