// The sensor types are spelled like the C++ ones: DHT22.
// ignore_for_file: constant_identifier_names
import 'interop.dart';

/// Adafruit's `DHT` (`DHT.h`, DHT sensor library 1.4.7): a DHT11, DHT12, DHT21 (AM2301) or DHT22 (AM2302) on one
/// data pin.
///
/// The sensor measures at most every 2 seconds, so a reading less than 2 s after the previous exchange returns the
/// previous result without talking to it. An exchange waits about 2.2 ms (about 21 ms on a DHT11) and then keeps
/// interrupts off for 4 to 5 ms while it times 40 bits; `millis()` loses about 3 ms each time.
@CppHeader('DHT.h')
@CppClass('DHT')
final class Dht {
  /// The sensor of [type] ([DHT11], [DHT12], [DHT21], [DHT22] or [AM2301]) with its data line on [pin]. The pin's
  /// internal pull-up is used; long wires need a 4.7–10 kΩ resistor to 5 V.
  external Dht(@CppPin() @CppType('uint8_t') int pin, @CppType('uint8_t') @CppRange(11, 22) int type);

  /// Sets up the pin. Call it once, e.g. in `setup()` or `OnStart`.
  external void begin();

  /// Talks to the sensor, unless the last exchange was less than 2 s ago, and returns whether that exchange gave a
  /// valid frame (its checksum matched). [force] talks to it anyway.
  external bool read({bool force = false});

  /// The temperature in °C (°F with [fahrenheit]) of the last valid exchange, after a [read]; `NaN` if it failed.
  external double readTemperature({bool fahrenheit = false, bool force = false});

  /// The relative humidity in percent, after a [read]; `NaN` if the exchange failed.
  external double readHumidity({bool force = false});

  /// The heat index (felt temperature) of [temperature] and [humidity], in °C (°F with [fahrenheit], and then
  /// [temperature] is in °F too).
  external double computeHeatIndex(double temperature, double humidity, {bool fahrenheit = false});

  /// [celsius] in °F.
  external double convertCtoF(double celsius);

  /// [fahrenheit] in °C.
  external double convertFtoC(double fahrenheit);
}

/// A DHT11 (blue, 0–50 °C in whole degrees, 20–80 %).
@CppName('DHT11')
const int DHT11 = 11;

/// A DHT12.
@CppName('DHT12')
const int DHT12 = 12;

/// A DHT21, also sold as AM2301.
@CppName('DHT21')
const int DHT21 = 21;

/// A DHT22 (white, −40–80 °C and 0–100 % in tenths), also sold as AM2302.
@CppName('DHT22')
const int DHT22 = 22;

/// An AM2301, the same sensor as [DHT21].
@CppName('AM2301')
const int AM2301 = 21;
