import 'package:unodar/unodar.dart';

class Settings {
  final int scale;
  int offset = 0;

  Settings(this.scale);

  int get doubled => scale * 2;
}

final settings = Settings(3);
final count = Signal<int>(0);
final scaled = Computed(() => count.value * settings.scale);
final shifted = Computed(() => count.value + settings.offset);
final twice = Computed(() => count.value + settings.doubled);

void main() => runDevice(
      Device(board: Uno(), children: [
        Every(Duration(seconds: 1), () {
          Serial.println(scaled.value + shifted.value + twice.value);
        }),
      ]),
    );
