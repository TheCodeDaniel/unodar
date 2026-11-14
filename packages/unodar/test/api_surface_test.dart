import 'package:test/test.dart';
import 'package:unodar/unodar.dart';

/// The constants are real Dart values so user code type-checks under `dart analyze`. The compiler emits them by
/// name (never by value), but the values still mirror Arduino.h so that the Dart view and the C++ view agree.
void main() {
  test('pin levels and modes mirror Arduino.h', () {
    expect([LOW, HIGH], [0, 1]);
    expect([INPUT, OUTPUT, INPUT_PULLUP], [0, 1, 2]);
  });

  test('analog pins and LED_BUILTIN mirror the Uno pins_arduino.h (variants/standard)', () {
    expect([A0, A1, A2, A3, A4, A5], [14, 15, 16, 17, 18, 19]);
    expect(LED_BUILTIN, 13);
  });

  test('interop annotations are const and keep their argument', () {
    const header = CppHeader('Servo.h');
    const cppClass = CppClass('Servo');
    const name = CppName('write');
    const type = CppType('uint8_t');
    const include = CppInclude('avr/wdt.h');
    const range = CppRange(33, 1059);
    expect([header.header, cppClass.name, name.name, type.type, include.header, range.min, range.max],
        ['Servo.h', 'Servo', 'write', 'uint8_t', 'avr/wdt.h', 33, 1059]);
  });

  // The widget declarations are never executed (their constructors are `external`), so these tests check their
  // types. `_goalProgram` and `_handles` below are compiled with this file: if a signature changes, this test file
  // stops compiling.
  test('Led, Button and Every are widgets, and Uno is a board', () {
    expect(_isSubtype<Led, Widget>(), isTrue);
    expect(_isSubtype<Button, Widget>(), isTrue);
    expect(_isSubtype<Every, Widget>(), isTrue);
    expect(_isSubtype<Uno, Board>(), isTrue);
    expect(_isSubtype<Device, Widget>(), isFalse, reason: 'a Device is the root, never a child');
  });

  test('the Phase 4 goal program and widget handles type-check', () {
    expect(_goalProgram, isA<void Function()>());
    expect(_handles, isA<void Function()>());
  });

  // Phase 5 (docs/SUBSET.md "Signals"). Like the widgets, signals are declarations only: never executed here.
  test('a Signal is a ReadonlySignal and not a widget; a Watch is a widget', () {
    expect(_isSubtype<Signal<int>, ReadonlySignal<int>>(), isTrue);
    expect(_isSubtype<Signal<int>, Widget>(), isFalse, reason: 'signals are state, never listed in children');
    expect(_isSubtype<ReadonlySignal<int>, Signal<int>>(), isFalse, reason: 'read-only signals have no setter');
    expect(_isSubtype<Watch<int>, Widget>(), isTrue);
  });

  test('the Phase 5 signal program, Watch callbacks and signal writes type-check', () {
    expect(_signalProgram, isA<void Function()>());
    expect(_signalWrites, isA<void Function()>());
    expect(_staticTypes, isA<void Function()>());
  });
}

bool _isSubtype<S, T>() => <S>[] is List<T>;

// The Phase 4 goal program (docs/SUBSET.md "Widgets: runDevice"), with every optional argument spelled out.
final _led = Led(pin: 13);
final _button = Button(
    pin: 2,
    onPressed: () {
      _led.toggle();
    });

void _goalProgram() => runDevice(
      Device(
        board: Uno(),
        serialBaud: 115200,
        children: [
          _led,
          _button,
          Every(Duration(milliseconds: 500), () {
            Serial.println('tick');
          }),
        ],
      ),
    );

void _handles() {
  _led.on();
  _led.off();
  _led.toggle();
}

// The Phase 5 signal program (docs/SUBSET.md "Signals", without `Computed`, which arrives in plan step 10).
final _count = Signal<int>(0);
final _ratio = Signal(0.5);
final _lit = Signal(true);
final _level = Signal(Uint8(3));
final _shown = Led(pin: 12, on: _lit);
final _logger = Watch(_count, (v) {
  Serial.println(v);
});

void _signalProgram() => runDevice(
      Device(
        board: Uno(),
        children: [
          _shown,
          _logger,
          Watch(_ratio, (double r) {
            _led.set(r > 0.5);
          }),
        ],
      ),
    );

void _signalWrites() {
  _count.value = _count.value + 1;
  _count.value++;
  _count.value--;
  _count.value += 2;
  _count.value -= 2;
  _ratio.value = _ratio.value / 2;
  _lit.value = !_lit.value;
  _level.value = Uint8(_level.value + 1);
  _led.set(_lit.value);
}

// Static types only, including the types inferred from each initial value: these typed list literals stop
// compiling if a type is wrong.
void _staticTypes() {
  final ReadonlySignal<int> readOnly = _count;
  final List<Object> checked = <Object>[
    <Signal<int>>[_count],
    <Signal<double>>[_ratio],
    <Signal<bool>>[_lit],
    <Signal<Uint8>>[_level],
    <int>[readOnly.value],
    <Widget>[_shown, _logger],
  ];
  checked.clear();
}
