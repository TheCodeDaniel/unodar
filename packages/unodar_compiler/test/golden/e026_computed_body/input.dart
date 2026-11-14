import 'package:unodar/unodar.dart';

int readSensor() => analogRead(A0);

final count = Signal<int>(0);
final block = Computed(() {
  return count.value;
});
final called = Computed(() => readSensor() + count.value);
final hardware = Computed(() => analogRead(A0));
final Computed<int> again = Computed(() => again.value + 1);

void main() => runDevice(Device(board: Uno(), children: []));
