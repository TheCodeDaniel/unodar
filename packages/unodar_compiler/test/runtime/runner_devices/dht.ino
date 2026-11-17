// Runner check (Phase 6 step 19): the DHT22 model of the avr8js runner. Hand-written C++ with DHT sensor library
// 1.4.7 on pin 2: two readings 2.5 s apart (each a full exchange: read() is forced), and one cached read right after.
#include <Arduino.h>
#include <DHT.h>

DHT dht(2, DHT22);

void report() {
  Serial.print(dht.read(true) ? "ok " : "fail ");
  Serial.print(dht.readTemperature(), 1);
  Serial.print(' ');
  Serial.println(dht.readHumidity(), 1);
}

void setup() {
  Serial.begin(9600);
  dht.begin();
  report();
  Serial.println(dht.readTemperature(), 1);  // cached: no second exchange
  delay(2500);
  report();
  Serial.println("DONE");
}

void loop() {}
