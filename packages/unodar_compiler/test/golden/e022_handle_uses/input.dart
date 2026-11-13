import 'package:unodar/unodar.dart';

// A widget handle is only used to call its methods or to be listed in children.
final led = Led(pin: 13);
final alias = led;

void use(Led target) {
  target.on();
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          Button(
              pin: 2,
              onPressed: () {
                final copy = led;
                Serial.println(led == led);
              }),
        ],
      ),
    );
