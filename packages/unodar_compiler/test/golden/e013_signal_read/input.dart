import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

int next() {
  count.value++;
  return count.value;
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Every(Duration(seconds: 1), () {
            Serial.println(count.value + next());
            count.value += next();
            count.value *= 2;
          }),
        ],
      ),
    );
