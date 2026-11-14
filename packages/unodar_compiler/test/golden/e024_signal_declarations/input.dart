import 'package:unodar/unodar.dart';

final count = Signal<int>(0);
var total = Signal<int>(0);

int read(Signal<int> s) => s.value;

Signal<int> pick() => count;

void bump() {
  final local = Signal(1);
  Signal<int> alias = count;
  count.value = local.value + alias.value;
}

void main() => runDevice(
      Device(
        board: Uno(),
        children: [
          Button(
              pin: 2,
              onPressed: () {
                bump();
                final inner = Signal(true);
              }),
        ],
      ),
    );
