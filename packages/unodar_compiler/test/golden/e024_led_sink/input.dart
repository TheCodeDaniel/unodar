import 'package:unodar/unodar.dart';

final a = Signal(true);
final b = Signal(false);
final pick = true;

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Led(pin: 13, on: pick ? a : b),
          Led(pin: 12, on: a),
        ],
      ),
    );
