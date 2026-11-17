import 'package:unodar/liquid_crystal.dart';
import 'package:unodar/unodar.dart';

final lcd = LiquidCrystal(12, 11, 5, 4, 3, 22);
final button = Button(
    pin: 12,
    onPressed: () {
      lcd.setCursor(40, 0);
      lcd.setCursor(0, 4);
    });

void main() => runDevice(Device(board: Uno(), children: [button]));
