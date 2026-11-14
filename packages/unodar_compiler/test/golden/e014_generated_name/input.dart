import 'package:unodar/unodar.dart';

// A top-level widget whose callback would get the same C++ name as a widget written in `children`
// (`unodar_button_0_onPressed`). A Led has no callback, so `button_1` does not clash.
final button_0 = Button(
    pin: 2,
    onPressed: () {
      Serial.println('a');
    });
final button_1 = Led(pin: 13);
final every_0 = Every(Duration(seconds: 1), () {
  Serial.println('d');
});

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          button_0,
          button_1,
          every_0,
          Button(
              pin: 3,
              onPressed: () {
                Serial.println('b');
              }),
          Button(
              pin: 4,
              onPressed: () {
                Serial.println('c');
              }),
          Every(Duration(seconds: 2), () {
            Serial.println('e');
          }),
        ],
      ),
    );
