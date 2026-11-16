import 'package:unodar/unodar.dart';

class Meter {
  late int level;
  external int raw;
  int _scale = 1;

  set scale(int value) => _scale = value;

  bool operator ==(Object other) => false;

  int read() => level * _scale;

  int get doubled => level * 2;

  static const int limit = 40;
}

void setup() {}

void loop() {}

class Shown {
  int n = 0;

  @override
  String toString() => 'Shown';

  @override
  int get hashCode => n;
}
