import 'package:unodar/unodar.dart';

final status = Led(pin: 13, on: lit);
final lit = Signal(true);

void main() => runDevice(Device(board: Uno(), children: [status]));
