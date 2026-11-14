import 'package:unodar/unodar.dart';

// Watch and delivery (plan step 6). Also an avr8js behaviour program: the initial value is delivered once at the
// end of setup(); a press on D2 writes `count` twice, which is delivered once; a press on D3 writes 0, which is
// delivered only if the count was not already 0. Watches of one signal run in `children` order.
final count = Signal<int>(0);
final logger = Watch(count, (v) {
  Serial.print('count ');
  Serial.println(v);
});
final plus = Button(
    pin: 2,
    onPressed: () {
      count.value++;
      count.value++;
    });
final clear = Button(
    pin: 3,
    onPressed: () {
      count.value = 0;
    });

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          logger,
          plus,
          clear,
          Watch(count, (int v) {
            Serial.print('twice ');
            Serial.println(v * 2);
          }),
        ],
      ),
    );
