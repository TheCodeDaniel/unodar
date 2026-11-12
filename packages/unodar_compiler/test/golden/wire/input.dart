import 'package:unodar/unodar.dart';

// Reads the accelerometer X axis of an MPU-6050 over I2C.
const int mpu = 0x68;
int failures = 0;

void setup() {
  Serial.begin(9600);
  Wire.begin();
  Wire.setClock(400000);
  Wire.beginTransmission(mpu);
  Wire.write(0x6B); // PWR_MGMT_1
  Wire.write(0); // wake up
  final status = Wire.endTransmission();
  if (status != 0) {
    failures += 1;
  }
}

void loop() {
  Wire.beginTransmission(mpu);
  Wire.write(0x3B); // ACCEL_XOUT_H
  Wire.endTransmission();
  final count = Wire.requestFrom(mpu, 2);
  if (count == 2 && Wire.available() >= 2) {
    final high = Wire.read();
    final low = Wire.read();
    // A 16-bit two's-complement reading from two bytes, in 32-bit int arithmetic.
    var x = high * 256 + low;
    if (x > 32767) {
      x -= 65536;
    }
    Serial.print('x=');
    Serial.println(x);
  } else {
    failures += 1;
    Serial.println(failures);
  }
  delay(100);
}
