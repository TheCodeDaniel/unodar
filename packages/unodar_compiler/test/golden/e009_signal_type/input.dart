import 'package:unodar/unodar.dart';

final ratio = Signal<num>(1);
final maybe = Signal<int?>(1);
final Signal<num> inferred = Signal(2);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Every(Duration(seconds: 1), () {
            Serial.println(ratio.value);
          }),
        ],
      ),
    );
