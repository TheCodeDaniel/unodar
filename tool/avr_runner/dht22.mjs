// A DHT22 (AM2302) temperature and humidity sensor on one data pin, for the avr8js runner (docs/PLAN.md Phase 6,
// DHT). The line is open-drain with a pull-up: the sensor only ever pulls it low or lets it go, as the real one does.
//
// The runner calls `mcuPin()` for every state change of the MCU's pin, with the CPU cycle. A start signal is the MCU
// driving the line low and then releasing it (input, with the pull-up); the datasheet (Aosong AM2302) asks for at
// least 0.8 ms low (typically 1 ms, at most 20 ms). After the release the model answers:
//
//   30 us released (Tgo), 80 us low, 80 us released (the response), then 40 bits, most significant first, each
//   50 us low followed by 26 us released for a 0 or 70 us for a 1, then 50 us low and the line is let go.
//
// The 40 bits are humidity x10 (16 bits), temperature x10 (16 bits, sign in the top bit) and a checksum, the low
// byte of the sum of the four bytes. The model reports what a real sensor would object to, as violations: a start
// pulse outside 0.8 to 20 ms, a start less than 2 s after the previous one (the sensor's sampling period), and the
// MCU driving the line while the sensor answers.
//
// Options (from run.mjs): `readings`, a list of { at (cycle), temperature, humidity } in time order, the reading of
// the last one whose time has come; `badChecksum` sends a wrong checksum; `oneUs` is the released time of a 1 bit
// (70 by default; a value below the 50 us low time makes every 1 look like a 0 to a decoder that compares them).

export class Dht22 {
  constructor({ clockHz, readings, badChecksum = false, oneUs = 70, drive }) {
    this.cyclesPerUs = clockHz / 1e6;
    this.cyclesPerMs = clockHz / 1e3;
    this.readings = readings;
    this.badChecksum = badChecksum;
    this.oneUs = oneUs;
    this.drive = drive; // drive(true) pulls the line low, drive(false) lets it go
    this.lowSince = null;
    this.answeringUntil = null;
    this.lastStart = null;
    this.log = [];
    this.violations = 0;
  }

  /// The MCU's pin state changed to [state] ('low', 'high', 'input' or 'input-pullup') at [cycle]. Returns the events
  /// to schedule, as [delay in cycles, callback] pairs, for the runner to add to the CPU clock.
  mcuPin(state, cycle) {
    const ms = (c) => (c / this.cyclesPerMs).toFixed(3);
    if (this.answeringUntil !== null && cycle < this.answeringUntil && (state === 'low' || state === 'high')) {
      this.violation(cycle, `the MCU drives the line ${state} while the sensor answers`);
    }
    if (state === 'low') {
      this.lowSince = cycle;
      return [];
    }
    if (this.lowSince === null) return [];
    const start = this.lowSince;
    this.lowSince = null;
    if (state === 'high') return []; // An output high ends no start signal.
    const lowMs = (cycle - start) / this.cyclesPerMs;
    if (lowMs < 0.8 || lowMs > 20) {
      this.violation(cycle, `start signal ${lowMs.toFixed(3)} ms low (0.8 to 20 ms)`);
      return [];
    }
    if (this.lastStart !== null && start - this.lastStart < 2000 * this.cyclesPerMs) {
      this.violation(cycle, `start ${((start - this.lastStart) / this.cyclesPerMs).toFixed(1)} ms after the previous one`
        + ' (at least 2000 ms)');
    }
    this.lastStart = start;
    const reading = this.readingAt(cycle);
    const bytes = this.frame(reading);
    const hex = bytes.map((b) => b.toString(16).padStart(2, '0')).join('');
    this.log.push(`${ms(cycle)} start ${lowMs.toFixed(3)} ms, sent T=${reading.temperature} H=${reading.humidity}`
      + ` frame=${hex}`);
    // The answer, as level changes relative to the release.
    const steps = [[30, true], [80, false], [80, true]];
    for (const byte of bytes) {
      for (let bit = 7; bit >= 0; bit--) {
        steps.push([50, false], [(byte >> bit) & 1 ? this.oneUs : 26, true]);
      }
    }
    steps.push([50, false]);
    const events = [];
    let at = 0;
    for (const [us, low] of steps) {
      at += us * this.cyclesPerUs;
      events.push([Math.round(at), () => this.drive(low)]);
    }
    this.answeringUntil = cycle + Math.round(at);
    return events;
  }

  readingAt(cycle) {
    let current = this.readings[0];
    for (const reading of this.readings) if (reading.at <= cycle) current = reading;
    return current;
  }

  frame({ temperature, humidity }) {
    const h = Math.round(humidity * 10);
    const t = Math.round(Math.abs(temperature) * 10) | (temperature < 0 ? 0x8000 : 0);
    const bytes = [h >> 8, h & 0xff, t >> 8, t & 0xff];
    const sum = (bytes[0] + bytes[1] + bytes[2] + bytes[3]) & 0xff;
    return [...bytes, this.badChecksum ? sum ^ 0x01 : sum];
  }

  violation(cycle, text) {
    this.violations++;
    this.log.push(`${(cycle / this.cyclesPerMs).toFixed(3)} violation ${text}`);
  }

  report() {
    return [...this.log, `violations ${this.violations}`];
  }
}
