import 'package:unodar/unodar.dart';

class Blinker {
  final int pin;
  Blinker(this.pin) {
    pinMode(pin, OUTPUT);
  }
}

class Quiet {
  final int pin;
  Quiet(this.pin) {}
}

class Named {
  final int pin;
  Named.on(this.pin);
}

class Fixed {
  final int pin;
  const Fixed(this.pin);
}

class Made {
  final int pin;
  Made(this.pin);
  factory Made.zero() => Made(0);
}

class Optional {
  final int pin;
  Optional([this.pin = 13]);
}

class Checked {
  final int pin;
  Checked(this.pin) : assert(pin >= 0);
}

void setup() {}

void loop() {}
