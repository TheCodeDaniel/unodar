import 'package:unodar/unodar.dart';

final led = Led(pin: 13);
final children = <Widget>[led];

// `children` must be written as a list literal in place.
void main() => runDevice(Device(board: Uno(), children: children));
