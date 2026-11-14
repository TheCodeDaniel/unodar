import 'package:unodar/unodar.dart';

final a = Signal<int>(0);
final b = Signal<int>(0);
final c = Signal<int>(0);
final last = Watch(c, (v) {
  a.value = v;
});

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          last,
          Watch(a, (v) {
            b.value = v;
          }),
          Watch(b, (v) {
            c.value = v;
          }),
        ],
      ),
    );
