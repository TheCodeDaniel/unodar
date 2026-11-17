import 'package:unodar/unodar.dart';

// `@CppUsesPins` belongs on an external object, with a map literal from pins 0 to 19 to non-empty roles.
@CppClass('Radio')
abstract final class Radio {
  external void send(@CppType('uint8_t') int value);
}

@CppUsesPins({2: 'IRQ', 3: 'CE'})
external final Radio good;

@CppUsesPins({20: 'IRQ'})
external final Radio outOfRange;

@CppUsesPins({2: ''})
external final Radio noRole;

@CppUsesPins({})
external final Radio empty;

@CppUsesPins({4: 'A'})
int counter = 0;

void setup() {
  good.send(1);
}

void loop() {}
