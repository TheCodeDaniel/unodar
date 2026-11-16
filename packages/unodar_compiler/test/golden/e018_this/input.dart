import 'package:unodar/unodar.dart';

class Node {
  int value = 0;

  void show() {
    Serial.println(this);
  }

  bool same() => this == this;
}

final node = Node();

void setup() {
  Serial.begin(9600);
  node.show();
}

void loop() {}
