import 'package:unodar/unodar.dart';

final count = Signal<int>(0);

class Limiter {
  final int top;

  Limiter(this.top);

  void clamp(int v) {
    if (v > top) count.value = top;
  }
}

final limiter = Limiter(10);

void main() => runDevice(
      Device(board: Uno(), children: [
        Button(
            pin: 2,
            onPressed: () {
              count.value++;
            }),
        Watch(count, (v) {
          limiter.clamp(v);
        }),
      ]),
    );
