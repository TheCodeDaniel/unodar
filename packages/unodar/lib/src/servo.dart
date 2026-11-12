import 'interop.dart';

/// A hobby servo (C++ `Servo`, from the Servo library: `arduino-cli lib install Servo`).
///
/// Declare one per servo at the top level: `final servo = Servo();`.
@CppHeader('Servo.h')
@CppClass('Servo')
final class Servo {
  external Servo();

  /// Attaches the servo to [pin]. [min] and [max] are the pulse widths in µs for 0° and 180°. Returns the servo's
  /// channel, or 255 on failure.
  @CppType('uint8_t')
  external int attach(@CppType('int') int pin, {@CppType('int') int min = 544, @CppType('int') int max = 2400});

  /// Turns to [angle] degrees (0 to 180). Values of 544 and above are taken as a pulse width in µs instead.
  external void write(@CppType('int') int angle);

  /// Sends pulses of [microseconds] µs.
  external void writeMicroseconds(@CppType('int') int microseconds);

  /// The last angle written, in degrees.
  @CppType('int')
  external int read();

  /// The current pulse width in µs.
  @CppType('int')
  external int readMicroseconds();

  /// Whether the servo is attached to a pin.
  external bool attached();

  /// Stops sending pulses and frees the pin.
  external void detach();
}
