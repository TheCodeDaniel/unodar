import 'package:unodar/unodar.dart';

// Interim (plan step 10): Computeds can be read, but delivering one (to a Watch or a bound Led) arrives in step 11,
// which replaces this golden with the positive `computed_watch`. Until then it is rejected, never delivered stale.
final count = Signal<int>(0);
final isOdd = Computed(() => count.value % 2 == 1);

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Led(pin: 13, on: isOdd),
          Watch(isOdd, (v) {}),
        ],
      ),
    );
