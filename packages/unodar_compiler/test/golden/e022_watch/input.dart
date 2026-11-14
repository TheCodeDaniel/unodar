import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
final unlisted = Watch(count, (v) {
  Serial.println(v);
});
final listed = Watch(count, (v) {
  Serial.println(v);
});

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          listed,
          listed,
          Button(
              pin: 2,
              onPressed: () {
                final inner = Watch(count, (v) {});
              }),
        ],
      ),
    );
