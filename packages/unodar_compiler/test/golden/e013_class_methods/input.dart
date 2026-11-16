import 'package:unodar/unodar.dart';

class Ticker {
  int count = 0;

  int next() {
    count++;
    return count;
  }

  int get twice => count * 2;

  void run() {
    Serial.println(count + next());
    Serial.println(twice + next());
  }
}

final ticker = Ticker();

void setup() {
  Serial.begin(9600);
}

void loop() {
  delay(ticker.count + ticker.next());
}
