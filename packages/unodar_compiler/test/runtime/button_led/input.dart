import 'package:unodar/unodar.dart';

final led = Led(pin: 13);
final button = Button(
    pin: 2,
    onPressed: () {
      led.toggle();
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          led,
          button,
          Every(Duration(milliseconds: 500), () {
            Serial.println('tick');
          }),
        ],
      ),
    );
