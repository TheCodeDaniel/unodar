/// The Phase 3 IR nodes (flash strings, method calls, bound objects, result conversions, raw C++, includes)
/// compile with avr-gcc for the Uno, ahead of the goldens that will produce them from Dart (docs/PLAN.md step 4).
/// Only libraries bundled with `arduino:avr` are used (Wire, SoftwareSerial); Servo is covered once CI installs it
/// (step 6).
@Tags(['arduino'])
library;

import 'package:test/test.dart';
import 'package:unodar_compiler/src/emitter/emitter.dart';

import 'arduino_toolchain.dart';
import 'phase3_ir.dart';

void main() {
  final gate = arduinoGate();

  test('the Phase 3 IR program compiles for arduino:avr:uno', () async {
    gate.check();
    final result = await compileSketch('phase3_ir', const CppEmitter(UnoTarget()).emit(phase3Program()));
    printOnFailure(result.rawOutput);
    expect(result.success, isTrue, reason: 'arduino-cli compile failed');
  }, skip: gate.skip, timeout: const Timeout(Duration(minutes: 2)));
}
