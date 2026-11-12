// Runtime check of 32-bit signed wraparound across INT32_MAX/INT32_MIN (docs/SUBSET.md "Known deviations": int
// overflow wraps because sketches are built with -fwrapv). Hand-written C++, run in avr8js by
// runtime_fidelity_test.dart. Every operand is read from a `volatile` global, so the compiler must load it at
// runtime and cannot fold the arithmetic, even with LTO. Prints one PASS/FAIL line per check, then DONE.
//
// Built without -fwrapv (the negative control), signed overflow is undefined and GCC simplifies `x + 1 > x` to
// true and `x - 1 < x` to true, so those checks print FAIL: proof that the flag is what makes them pass.
#include <Arduino.h>

volatile int32_t nearMax = 2147483647;           // INT32_MAX
volatile int32_t nearMin = -2147483647 - 1;      // INT32_MIN
volatile int32_t lastTick = 2147483637;          // INT32_MAX - 10: a timer stamp taken just before the wrap
volatile int32_t interval = 20;
volatile uint32_t rawMillis = 0x8000000AUL;      // millis() 21 ms later, past 2^31

static void check(const __FlashStringHelper *name, bool ok) {
  Serial.print(ok ? F("PASS ") : F("FAIL "));
  Serial.println(name);
}

void setup() {
  Serial.begin(115200);
  const int32_t max = nearMax;
  const int32_t min = nearMin;
  const int32_t last = lastTick;
  const int32_t now = int32_t(rawMillis);       // what unodar emits for millis(): int32_t(millis())

  check(F("now - last == 21 across the wrap"), now - last == 21);
  check(F("now - last >= interval across the wrap"), now - last >= interval);
  check(F("now > last is false across the wrap"), !(now > last));
  check(F("last + 21 == now (addition wraps)"), last + 21 == now);
  check(F("INT32_MAX + 1 == INT32_MIN"), max + 1 == min);
  check(F("INT32_MIN - 1 == INT32_MAX"), min - 1 == max);
  check(F("x + 1 > x is false for INT32_MAX"), !(max + 1 > max));
  check(F("x - 1 < x is false for INT32_MIN"), !(min - 1 < min));
  check(F("-INT32_MIN == INT32_MIN"), -min == min);
  Serial.println(F("DONE"));
}

void loop() {}
