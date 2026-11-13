// Runtime check of the widget runtime header (runtime/unodar_widgets.h, docs/SUBSET.md "Widgets: runDevice").
// Hand-written C++, run in avr8js by runtime_fidelity_test.dart with the header next to it. The debounce and timer
// logic is driven through the overloads that take the time (and the raw button reading), so simulated time can
// jump anywhere, including across the 2^32 wrap of millis(). Start times are `volatile`, so nothing is folded at
// compile time. Prints one PASS/FAIL line per check, then DONE.
#include <Arduino.h>
#include "unodar_widgets.h"

// The constructors are constexpr, so generated widget globals are constant-initialized (no constructor code runs
// before setup()). These lines do not compile otherwise.
constexpr unodar::Led constantLed(13);
constexpr unodar::Button constantButton(2);
constexpr unodar::Every constantEvery(2147483647);

// RAM per widget object on the Uno (docs/SUBSET.md, size budgets): pin + state; pin + two flags + a uint32_t
// timestamp; interval + last tick.
static_assert(sizeof(unodar::Led) == 2, "Led is 2 bytes");
static_assert(sizeof(unodar::Button) == 7, "Button is 7 bytes");
static_assert(sizeof(unodar::Every) == 8, "Every is 8 bytes");

volatile uint32_t start = 1000;
volatile uint32_t nearWrap = 0xFFFFFF00UL;  // 256 ms before millis() wraps to 0

// Declared before the first function: arduino-cli inserts its generated prototypes there.
// A raw button signal: `down` from `at` (ms after the start) until the next change.
struct Change {
  uint32_t at;
  bool down;
};

static void check(const __FlashStringHelper *name, bool ok) {
  Serial.print(ok ? F("PASS ") : F("FAIL "));
  Serial.println(name);
}

// Polls `button` every millisecond for `duration` ms from `t0`, following `changes`. Returns the number of presses
// and stores the time (relative to t0) of the first one in `first`.
static int pollButton(unodar::Button &button, uint32_t t0, uint32_t duration, const Change *changes, int count,
                      uint32_t &first) {
  int presses = 0;
  bool down = false;
  int next = 0;
  for (uint32_t t = 0; t <= duration; t++) {
    while (next < count && changes[next].at == t) down = changes[next++].down;
    if (button.update(t0 + t, down)) {
      if (presses == 0) first = t;
      presses++;
    }
  }
  return presses;
}

static void buttonChecks() {
  const uint32_t t0 = start;

  // Two presses with contact bounce, a bouncing release, and a 30 ms glitch that is too short to count.
  const Change bouncy[] = {
      {10, true}, {12, false}, {15, true}, {18, false}, {20, true},   // press, stable from 20 -> press at 70
      {300, false}, {303, true}, {306, false},                        // release with bounce: nothing
      {500, true},                                                    // clean press -> press at 550
      {700, false}, {800, true}, {830, false},                        // release, then a 30 ms glitch: nothing
  };
  unodar::Button button(2);
  button.begin(t0, false);
  uint32_t first = 0;
  const int presses = pollButton(button, t0, 1000, bouncy, sizeof(bouncy) / sizeof(bouncy[0]), first);
  check(F("a bouncing press, a clean press and a glitch give exactly 2 presses"), presses == 2);
  check(F("the first press is reported 50 ms after the reading settles"), first == 70);

  // Held at power-up: no press until it is released and pressed again.
  const Change held[] = {{1000, false}, {1100, true}};
  unodar::Button heldButton(3);
  heldButton.begin(t0, true);
  uint32_t heldFirst = 0;
  bool down = true;
  int heldPresses = 0;
  for (uint32_t t = 0; t <= 1300; t++) {
    for (const Change &c : held) {
      if (c.at == t) down = c.down;
    }
    if (heldButton.update(t0 + t, down)) {
      if (heldPresses == 0) heldFirst = t;
      heldPresses++;
    }
  }
  check(F("a button held at power-up is not a press"), heldPresses == 1 && heldFirst == 1150);

  // Debounce across the millis() wrap: the reading goes LOW 16 ms before the wrap and stays there.
  const Change wrapped[] = {{16, true}};
  unodar::Button wrapButton(4);
  wrapButton.begin(nearWrap + 224, false);  // 0xFFFFFFE0
  uint32_t wrapFirst = 0;
  const int wrapPresses = pollButton(wrapButton, nearWrap + 224, 200, wrapped, 1, wrapFirst);
  check(F("debounce works across the millis() wrap"), wrapPresses == 1 && nearWrap + 224 + wrapFirst == 34);
}

static void everyChecks() {
  const uint32_t t0 = start;

  // Polled every millisecond for 10 s: 20 ticks, the first one interval after begin().
  unodar::Every every(500);
  every.begin(t0);
  int ticks = 0;
  uint32_t firstTick = 0;
  for (uint32_t t = 1; t <= 10000; t++) {
    if (every.due(t0 + t)) {
      if (ticks == 0) firstTick = t;
      ticks++;
    }
  }
  check(F("Every(500) ticks 20 times in 10 s"), ticks == 20);
  check(F("the first tick comes one interval after begin()"), firstTick == 500);

  // Polled every 7 ms: tick k is reported at the first poll at or after k * 500, so lateness never accumulates.
  unodar::Every jittery(500);
  jittery.begin(t0);
  int jitteryTicks = 0;
  uint32_t lastTick = 0;
  for (uint32_t t = 7; t <= 10000; t += 7) {
    if (jittery.due(t0 + t)) {
      jitteryTicks++;
      lastTick = t;
    }
  }
  check(F("Every is drift-free when polled late"), jitteryTicks == 19 && lastTick == 9506);

  // A callback ran for 2.6 s: five ticks are owed, reported one per call; then the schedule continues on time.
  unodar::Every late(500);
  late.begin(t0);
  int owed = 0;
  while (owed < 10 && late.due(t0 + 2600)) owed++;
  const bool onTime = !late.due(t0 + 2999) && late.due(t0 + 3000) && !late.due(t0 + 3000);
  check(F("missed ticks are caught up one per call"), owed == 5 && onTime);

  // Across the millis() wrap: begin() 256 ms before it, polled every millisecond for 1 s.
  unodar::Every wrapping(100);
  wrapping.begin(nearWrap);
  int wrapTicks = 0;
  bool tickAfterWrap = false;
  for (uint32_t t = 1; t <= 1000; t++) {
    if (wrapping.due(nearWrap + t)) {
      wrapTicks++;
      if (nearWrap + t == 44) tickAfterWrap = true;  // the third tick, 300 ms after begin(), wrapped to 44
    }
  }
  check(F("Every ticks on schedule across the millis() wrap"), wrapTicks == 10 && tickAfterWrap);
}

// The pin side, through the runner's GPIO ports: an output pin reads back its own level, and an input nobody drives
// reads HIGH when its pull-up is on.
static void pinChecks() {
  unodar::Led led(13);
  led.begin();
  const bool startsOff = digitalRead(13) == LOW;
  led.on();
  const bool on = digitalRead(13) == HIGH;
  led.toggle();
  const bool toggledOff = digitalRead(13) == LOW;
  led.toggle();
  const bool toggledOn = digitalRead(13) == HIGH;
  led.off();
  check(F("Led starts off; on, toggle, toggle, off drive the pin"),
        startsOff && on && toggledOff && toggledOn && digitalRead(13) == LOW);

  unodar::Button released(7);
  released.begin();
  bool anyPress = false;
  for (int i = 0; i < 100; i++) anyPress = released.pressed() || anyPress;
  check(F("an unconnected button reads HIGH through the pull-up and is never pressed"),
        digitalRead(7) == HIGH && !anyPress);
}

void setup() {
  Serial.begin(115200);
  buttonChecks();
  everyChecks();
  pinChecks();
  Serial.println(F("DONE"));
}

void loop() {}
