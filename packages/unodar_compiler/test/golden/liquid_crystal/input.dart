import 'package:unodar/liquid_crystal.dart';
import 'package:unodar/unodar.dart';

// The LiquidCrystal wrapper (Phase 6 step 17), imported on its own, wired as in Arduino's examples. Every wrapped
// method once. Also an avr8js behaviour program: the runner's HD44780 model shows the screen and checks the timings.
final lcd = LiquidCrystal(12, 11, 5, 4, 3, 2);

void setup() {
  Serial.begin(9600);
  lcd.begin(16, 2);
  lcd.print('booting');
  lcd.clear();
  lcd.print('Temp ');
  lcd.print(21.5, digits: 1);
  lcd.write(223);
  lcd.print('C');
  lcd.setCursor(0, 1);
  lcd.print('Heater ');
  lcd.print(true);
  lcd.cursor();
  lcd.blink();
  lcd.noBlink();
  lcd.noDisplay();
  lcd.display();
  lcd.scrollDisplayLeft();
  lcd.scrollDisplayRight();
  lcd.scrollDisplayLeft();
  lcd.home();
  lcd.noCursor();
  lcd.setCursor(15, 1);
  lcd.cursor();
  Serial.println('DONE');
}

void loop() {}
