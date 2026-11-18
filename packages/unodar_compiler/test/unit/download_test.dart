import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unodar_compiler/src/toolchain/setup.dart';

/// The real download of `unodar setup`, against a local HTTP server: it reports progress, and gives up when no data
/// arrives for a while instead of hanging (found on a slow connection in the fresh-machine test).
void main() {
  late HttpServer server;
  final body = List<int>.generate(1000000, (i) => i % 251);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response..contentLength = body.length;
      if (request.uri.path == '/stall') {
        response.add(body.sublist(0, 1000));
        await response.flush();
        await Future<void>.delayed(const Duration(seconds: 5)); // then nothing more for a long time
      } else {
        response.add(body);
      }
      await response.close();
    });
  });
  tearDown(() => server.close(force: true));

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('downloads the whole file and reports progress', () async {
    final out = StringBuffer();
    final bytes = await httpFetch(const {}, out, progressEvery: 250000)(url('/file'));
    expect(bytes, body);
    expect('$out', contains('  1.0 MB of 1.0 MB'));
  });

  test('gives up when no data arrives for the idle timeout', () async {
    final out = StringBuffer();
    final fetch = httpFetch(const {}, out, idleTimeout: const Duration(milliseconds: 500));
    await expectLater(fetch(url('/stall')), throwsA(isA<TimeoutException>()));
  });

  test('setup turns a stalled download into exit 3 with the retry advice', () async {
    final err = StringBuffer();
    final message = setupErrorFor(TimeoutException('no data', const Duration(seconds: 60)), url('/stall'));
    err.write(message);
    expect('$err', contains('no data arrived for 60 s'));
    expect('$err', contains('run `unodar setup` again'));
  });
}
