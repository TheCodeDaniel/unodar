import 'package:unodar/dht.dart';
import 'package:unodar/unodar.dart';

// The DHT wrapper (Phase 6 step 19), every wrapped method once, on a DHT22 with its data line on pin 2. Also an
// avr8js behaviour program against the runner's DHT22 model: the values, the 2 s cache (four reads, one exchange),
// and the millis() ticks an exchange loses, stamped on pin 13 against the simulated time.
const int dataPin = 2;
const int stampPin = 13;

final sensor = Dht(dataPin, DHT22);

void report() {
  final ok = sensor.read();
  final celsius = sensor.readTemperature();
  final percent = sensor.readHumidity();
  Serial.print(ok);
  Serial.print(' ');
  Serial.print(celsius, digits: 1);
  Serial.print(' ');
  Serial.println(percent, digits: 1);
}

void setup() {
  Serial.begin(9600);
  pinMode(stampPin, OUTPUT);
  sensor.begin();
  report();
  report();
  Serial.println(sensor.readTemperature(fahrenheit: true), digits: 2);
  Serial.println(sensor.computeHeatIndex(30.0, 70.0), digits: 2);
  Serial.println(sensor.convertCtoF(100.0), digits: 1);
  Serial.println(sensor.convertFtoC(212.0), digits: 1);
  final before = millis();
  digitalWrite(stampPin, HIGH);
  delay(2100);
  sensor.read(force: true);
  final after = millis();
  digitalWrite(stampPin, LOW);
  Serial.println(after - before);
  Serial.println('DONE');
}

void loop() {}
