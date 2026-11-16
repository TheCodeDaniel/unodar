import 'package:unodar/unodar.dart';

abstract class Shape {}

class Box<T> {}

mixin Glow {}

class Lamp with Glow {}

class Panel implements Shape {}

class Fast extends Box<int> {}

sealed class Mode {}

base class Part {}

interface class Port {}

mixin class Blend {}

void setup() {}

void loop() {}
