/// DHT11 and DHT22 (AM2302) temperature and humidity sensors (Adafruit's DHT sensor library 1.4.7, from the library
/// index, with its dependency Adafruit Unified Sensor 1.1.15). Import it on its own:
/// `import 'package:unodar/dht.dart';`.
///
/// ```dart
/// final sensor = Dht(2, DHT22);          // data line on pin 2
/// sensor.begin();
/// if (sensor.read()) {
///   final celsius = sensor.readTemperature();
///   final percent = sensor.readHumidity();
/// }
/// ```
///
/// See docs/SUBSET.md "DHT" for the waits, the time with interrupts off, the costs and what is verified in the
/// simulator.
library;

export 'src/dht.dart';
