import 'package:unodar/unodar.dart';

class Toggle {
  bool on = false;

  void flip() {
    on = !on;
  }

  void later() {
    final f = () => flip();
  }
}

final toggle = Toggle();

void main() => runDevice(
      Device(board: Uno(), children: [
        Button(pin: 2, onPressed: toggle.flip),
      ]),
    );
