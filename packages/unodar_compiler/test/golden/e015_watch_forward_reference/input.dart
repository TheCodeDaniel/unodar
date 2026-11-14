import 'package:unodar/unodar.dart';

final early = Watch(count, (v) {
  Serial.println(v);
});
final count = Signal<int>(0);

void main() => runDevice(Device(board: Uno(), children: [early]));
