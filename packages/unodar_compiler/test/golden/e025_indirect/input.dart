import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

void store(int v) {
  count.value = v;
}

void bump(int v) {
  store(v + 1);
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Watch(count, (v) {
            bump(v);
          }),
        ],
      ),
    );
