// Regression (Phase 6 step 10): annotation placement skipped the members of the user's own classes, so these
// annotations were silently ignored. Each is misplaced: no interop annotation applies inside a user class.
import 'package:unodar/unodar.dart';

enum Mode {
  @CppName('OFF')
  off,
  on,
}

final class Meter {
  Meter(@CppPin() this.pin, {@CppRange(0, 9) this.scale = 1});

  @CppType('uint8_t')
  final int pin;
  final int scale;
  int total = 0;

  @CppName('MAX')
  static const int limit = 100;

  @CppName('read')
  int value() => total * scale;

  @CppType('uint16_t')
  int get doubled => total * 2;

  void add(@CppType('uint8_t') int amount) {
    total += amount;
  }

  @CppName('make')
  static int twice(@CppRange(0, 9) int x) => x * 2;
}

final Meter meter = Meter(3);

void setup() {}

void loop() {
  meter.add(1);
}
