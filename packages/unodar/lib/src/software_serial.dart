import 'interop.dart';

/// Arduino's `SoftwareSerial` (`SoftwareSerial.h`, in the AVR core): 8N1 serial on any two pins. Only one object
/// receives at a time, the one that called [begin] or [listen] last; every object can send.
///
/// Sending a byte keeps interrupts off for 9 bit times (0.94 ms at 9600 baud), so a byte cannot be received while
/// one is being sent, by this or any other object.
@CppHeader('SoftwareSerial.h')
@CppClass('SoftwareSerial')
@CppPrint()
final class SoftwareSerial {
  /// Receives on [rx] and sends on [tx], pins 2 to 19: pins 0 and 1 are `Serial`'s (and the USB connection's).
  /// [inverseLogic] inverts both lines (idle low), for some RS-232 level shifters.
  external SoftwareSerial(
      @CppPin() @CppRange(2, 19) @CppType('uint8_t') int rx, @CppPin() @CppRange(2, 19) @CppType('uint8_t') int tx,
      {bool inverseLogic = false});

  /// Starts the port at [baud] bits per second (300 to 115200; 57600 and below receive reliably) and makes this the
  /// object that receives.
  external void begin(@CppType('long') @CppRange(300, 115200) int baud);

  /// Stops receiving (if this object was receiving).
  external void end();

  /// Makes this the object that receives; the others stop, and their unread bytes are lost. True if it was not
  /// receiving before.
  external bool listen();

  /// Whether this object is the one that receives.
  external bool isListening();

  /// Whether a byte was lost because the receive buffer was full (63 bytes) since the last call; clears it.
  external bool overflow();

  /// The number of received bytes waiting, 0 to 63 (0 unless this object is receiving).
  @CppType('int')
  external int available();

  /// The next received byte, 0 to 255, or -1 if there is none.
  @CppType('int')
  external int read();

  /// Like [read], without removing the byte.
  @CppType('int')
  external int peek();

  /// Sends one byte (0 to 255); returns 1.
  @CppType('size_t')
  external int write(@CppType('uint8_t') int value);

  /// Sends [value] as text, like `Serial.print`. A string must be a literal. [digits] applies to a `double` only.
  external void print(Object value, {int digits = 2});

  /// Like [print], then a line break. `println('')` sends only the line break.
  external void println(Object value, {int digits = 2});
}
