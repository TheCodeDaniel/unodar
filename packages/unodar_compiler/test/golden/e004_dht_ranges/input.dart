import 'package:unodar/dht.dart';
import 'package:unodar/unodar.dart';

// The DHT constructor: a pin 0 to 19 (E004), not shared with a widget (E022), and a sensor type 11 to 22 (E004).
final outdoor = Dht(20, DHT22);
final indoor = Dht(3, 10);
final greenhouse = Dht(4, 23);
final button = Button(pin: 3, onPressed: () {});

void main() => runDevice(Device(board: Uno(), children: [button]));
