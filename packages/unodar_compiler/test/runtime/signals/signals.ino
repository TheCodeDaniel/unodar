// Runtime check of unodar::Signal<T> (runtime/unodar_widgets.h, docs/SUBSET.md "Signals"). Hand-written C++, run
// in avr8js by runtime_fidelity_test.dart with the header next to it. Values come from `volatile` globals, so
// nothing is folded at compile time. Prints one PASS/FAIL line per check, then DONE.
//
// The two-phase delivery at the end is a hand-written model of the generated unodar_deliver() (plan step 6): take
// every mark and value first, then run the observers. NAIVE_DELIVERY 1 (a negative control) interleaves taking and
// running, which lets a write made during delivery arrive in the same pass.
#include <Arduino.h>
#include <math.h>
#include "unodar_widgets.h"

#define NAIVE_DELIVERY 0

// The constructor is constexpr, so generated signal globals are constant-initialized. These do not compile otherwise.
constexpr unodar::Signal<int32_t> constantInt(-2147483647L - 1);
constexpr unodar::Signal<float> constantFloat(1.5f);
constexpr unodar::Signal<bool> constantBool(true);

// RAM per signal on the Uno (docs/SUBSET.md "Signals", size budgets): the value plus a 1-byte mark, no padding.
static_assert(sizeof(unodar::Signal<int32_t>) == 5, "Signal<int32_t> is 5 bytes");
static_assert(sizeof(unodar::Signal<float>) == 5, "Signal<float> is 5 bytes");
static_assert(sizeof(unodar::Signal<int16_t>) == 3, "Signal<int16_t> is 3 bytes");
static_assert(sizeof(unodar::Signal<uint16_t>) == 3, "Signal<uint16_t> is 3 bytes");
static_assert(sizeof(unodar::Signal<uint8_t>) == 2, "Signal<uint8_t> is 2 bytes");
static_assert(sizeof(unodar::Signal<bool>) == 2, "Signal<bool> is 2 bytes");

// Led::set is public (Led.set(bool), and the target of Led(on: …)). This does not compile otherwise.
void (unodar::Led::*const ledSet)(bool) = &unodar::Led::set;

volatile int32_t zero = 0;
volatile int32_t one = 1;
volatile int32_t seven = 7;
volatile float floatZero = 0.0f;
volatile float minusZero = -0.0f;

static void check(const __FlashStringHelper *name, bool ok) {
  Serial.print(ok ? F("PASS ") : F("FAIL "));
  Serial.println(name);
}

static void markChecks() {
  unodar::Signal<int32_t> s(zero);
  const bool first = s.take();
  const bool second = s.take();
  check(F("a signal starts changed, and take() clears the mark"), first && !second);

  s.set(zero);
  check(F("an equal write does not mark the signal"), !s.take());

  s.set(seven);
  check(F("a different write stores the value and marks the signal"), s.take() && s.value() == 7);

  s.set(one);
  s.set(seven);
  s.set(zero);
  check(F("several writes are one mark with the last value"), s.take() && s.value() == 0 && !s.take());

  s.set(one);
  s.set(zero);
  check(F("0 -> 1 -> 0 still marks the signal (coalesced, not compared with the last delivery)"),
        s.take() && s.value() == 0);
}

static void floatChecks() {
  unodar::Signal<float> nanSignal(NAN);
  nanSignal.take();
  nanSignal.set(NAN);
  const bool marked = nanSignal.take();
  nanSignal.set(NAN);
  check(F("writing NaN onto NaN always marks (NaN != NaN, as in Dart)"), marked && nanSignal.take());

  unodar::Signal<float> zeroSignal(floatZero);
  zeroSignal.take();
  zeroSignal.set(minusZero);
  check(F("writing -0.0 onto 0.0 does not mark and keeps 0.0 (equal, as in Dart)"),
        !zeroSignal.take() && !signbit(zeroSignal.value()));
}

static void sizedChecks() {
  unodar::Signal<uint8_t> byteSignal{uint8_t(zero)};
  byteSignal.set(uint8_t(255 + zero));
  unodar::Signal<int16_t> shortSignal{int16_t(zero)};
  shortSignal.set(int16_t(-32768 + zero));
  check(F("sized signals keep their full range"), byteSignal.value() == 255 && shortSignal.value() == -32768);
}

// Two signals: `a` is declared first, and the Watch of `a` writes `b` (a -> b, no cycle). The Watch of `b` records
// the pass it ran in and the value it got.
unodar::Signal<int32_t> a(0);
unodar::Signal<int32_t> b(0);
int32_t pass = 0;
int32_t bRunPass = -1;
int32_t bRunValue = -1;
int32_t bRuns = 0;

static void watchA(int32_t v) { b.set(v * 10); }
static void watchB(int32_t v) {
  bRunPass = pass;
  bRunValue = v;
  bRuns++;
}

static void deliver() {
#if NAIVE_DELIVERY
  if (a.take()) watchA(a.value());
  if (b.take()) watchB(b.value());
#else
  const bool aChanged = a.take();
  const int32_t aValue = a.value();
  const bool bChanged = b.take();
  const int32_t bValue = b.value();
  if (aChanged) watchA(aValue);
  if (bChanged) watchB(bValue);
#endif
}

static void deliveryChecks() {
  deliver();  // The setup delivery: both start changed.
  bRuns = 0;
  bRunPass = -1;
  for (pass = 1; pass <= 3; pass++) {
    if (pass == 1) a.set(seven);  // Phase 1 (inputs) of pass 1.
    deliver();
  }
  check(F("a write made during delivery is delivered in the next pass, whatever the declaration order"),
        bRunPass == 2);
  check(F("the next pass delivers the written value exactly once"), bRuns == 1 && bRunValue == 70);
}

void setup() {
  Serial.begin(9600);
  markChecks();
  floatChecks();
  sizedChecks();
  deliveryChecks();
  Serial.println(F("DONE"));
}

void loop() {}
