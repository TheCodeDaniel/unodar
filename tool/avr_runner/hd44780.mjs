// An HD44780 character LCD controller, wired in 4-bit mode (RS, E, D4-D7; R/W tied to GND), for the avr8js runner
// (docs/PLAN.md Phase 6, LiquidCrystal). The runner calls `pin()` for every level change of those six pins, with the
// CPU cycle; the model latches a nibble on each falling edge of E, decodes instructions as the datasheet (Hitachi
// HD44780U, rev. 0.0) describes, keeps the display data RAM, and reports every timing violation it can see:
//
// - an E pulse shorter than 450 ns (PW_EH);
// - D4-D7 or RS changing while E is high (setup and hold);
// - E rising while the previous instruction is still executing: 37 us, 1.52 ms for clear and home, and during the
//   initialization by instruction 4.1 ms after the first function set and 100 us after the second (figure 24).
//
// Like the real chip it starts in 8-bit mode, where each E pulse is one instruction whose low four bits are 0 (D0-D3
// are not connected), and switches with the DL bit of a function set. So a program that runs the initialization
// sequence again while the chip is already in 4-bit mode resynchronizes it, as LiquidCrystal does when begin() follows
// its constructor.
//
// The datasheet also asks for 40 ms after power-on before the first instruction. That is reported as a fact, not as
// a violation (`first instruction at … ms`): LiquidCrystal 1.0.7 means to wait 50 ms, but delayMicroseconds() takes
// a 16-bit count and four steps per microsecond at 16 MHz, so delayMicroseconds(50000) wraps to about 0.85 ms. Real
// modules cope through the initialization by instruction above; whether one does is a question for the board.

const twoLineRows = [0x00, 0x40];
const lineLength = 40; // DDRAM per line in 2-line mode (0x00-0x27, 0x40-0x67)

export class Hd44780 {
  constructor({ clockHz, cols = 16, rows = 2 }) {
    this.cycleNs = 1e9 / clockHz;
    this.cyclesPerUs = clockHz / 1e6;
    this.cols = cols;
    this.rows = rows;
    this.levels = { rs: false, e: false, d4: false, d5: false, d6: false, d7: false };
    this.eRoseAt = null;
    this.eightBit = true;
    this.highNibble = null; // first half of a 4-bit transfer
    this.twoLine = false;
    this.ddram = new Uint8Array(128).fill(0x20);
    this.address = 0; // address counter (DDRAM, or CGRAM when cgram is true)
    this.cgram = false;
    this.increment = true;
    this.shiftOnWrite = false;
    this.shift = 0; // positions the display content has moved right
    this.displayOn = false;
    this.cursorOn = false;
    this.blinkOn = false;
    this.busyUntil = 0;
    this.busyFor = '';
    this.initFunctionSets = 0; // function sets in 8-bit mode since power-on, for the init timings
    this.firstInstructionAt = null;
    this.log = [];
    this.violations = 0;
  }

  /// [role] is rs, e, d4, d5, d6 or d7.
  pin(role, high, cycle) {
    const was = this.levels[role];
    this.levels[role] = high;
    if (was === high) return;
    if (role === 'e') {
      if (high) this.eRise(cycle);
      else this.eFall(cycle);
    } else if (this.levels.e) {
      this.violation(cycle, `${role.toUpperCase()} changed while E was high`);
    }
  }

  eRise(cycle) {
    this.eRoseAt = cycle;
    this.firstInstructionAt ??= cycle;
    // The second nibble of a 4-bit transfer may follow at once; anything else waits for the busy time.
    if (this.highNibble === null && cycle < this.busyUntil) {
      this.violation(cycle, `E rose ${this.us(this.busyUntil - cycle)} us too early, while ${this.busyFor} was busy`);
    }
  }

  eFall(cycle) {
    if (this.eRoseAt !== null && (cycle - this.eRoseAt) * this.cycleNs < 450) {
      this.violation(cycle, `E pulse of ${Math.round((cycle - this.eRoseAt) * this.cycleNs)} ns (minimum 450 ns)`);
    }
    const nibble =
      (this.levels.d4 ? 1 : 0) | (this.levels.d5 ? 2 : 0) | (this.levels.d6 ? 4 : 0) | (this.levels.d7 ? 8 : 0);
    if (this.eightBit) {
      this.execute(nibble << 4, this.levels.rs, cycle);
    } else if (this.highNibble === null) {
      this.highNibble = nibble;
    } else {
      const value = (this.highNibble << 4) | nibble;
      this.highNibble = null;
      this.execute(value, this.levels.rs, cycle);
    }
  }

  execute(value, rs, cycle) {
    const hex = `0x${value.toString(16).padStart(2, '0')}`;
    this.log.push(`${cycle} ${rs ? 'data' : this.eightBit ? 'cmd8' : 'cmd'} ${hex}`);
    let busyUs = 37;
    let name = rs ? `data ${hex}` : `command ${hex}`;
    if (rs) {
      this.writeData(value);
    } else if (value & 0x80) {
      this.cgram = false;
      this.address = this.validDdram(value & 0x7f);
    } else if (value & 0x40) {
      this.cgram = true;
      this.address = value & 0x3f;
    } else if (value & 0x20) {
      name = 'function set';
      if (this.eightBit) {
        this.initFunctionSets++;
        if (this.initFunctionSets === 1) busyUs = 4100;
        else if (this.initFunctionSets === 2) busyUs = 100;
      }
      this.eightBit = (value & 0x10) !== 0;
      this.twoLine = (value & 0x08) !== 0;
    } else if (value & 0x10) {
      const right = (value & 0x04) !== 0;
      if (value & 0x08) this.shift += right ? 1 : -1;
      else this.address = this.step(this.address, right);
    } else if (value & 0x08) {
      this.displayOn = (value & 0x04) !== 0;
      this.cursorOn = (value & 0x02) !== 0;
      this.blinkOn = (value & 0x01) !== 0;
    } else if (value & 0x04) {
      this.increment = (value & 0x02) !== 0;
      this.shiftOnWrite = (value & 0x01) !== 0;
    } else if (value & 0x02) {
      name = 'return home';
      busyUs = 1520;
      this.cgram = false;
      this.address = 0;
      this.shift = 0;
    } else if (value & 0x01) {
      name = 'clear display';
      busyUs = 1520;
      this.ddram.fill(0x20);
      this.cgram = false;
      this.address = 0;
      this.increment = true;
      this.shift = 0;
    }
    this.busyUntil = cycle + busyUs * this.cyclesPerUs;
    this.busyFor = name;
  }

  writeData(value) {
    if (this.cgram) {
      this.address = (this.address + 1) & 0x3f;
      return;
    }
    this.ddram[this.address] = value;
    this.address = this.step(this.address, this.increment);
    if (this.shiftOnWrite) this.shift += this.increment ? -1 : 1;
  }

  /// The DDRAM address after [address] moving right (or left), wrapping as the chip does.
  step(address, right) {
    if (!this.twoLine) return (address + (right ? 1 : 79)) % 80;
    if (right) return address === 0x27 ? 0x40 : address === 0x67 ? 0x00 : address + 1;
    return address === 0x00 ? 0x67 : address === 0x40 ? 0x27 : address - 1;
  }

  validDdram(address) {
    if (!this.twoLine) return address < 80 ? address : 0;
    if (address < 0x28 || (address >= 0x40 && address < 0x68)) return address;
    return address < 0x40 ? 0x00 : 0x40;
  }

  /// The DDRAM address shown at [row], [col], for a display of this.cols x this.rows (LiquidCrystal's row offsets:
  /// 0x00, 0x40, then each plus cols for a 4-row display).
  shownAddress(row, col) {
    if (!this.twoLine) return (((row * this.cols + col - this.shift) % 80) + 80) % 80;
    const line = twoLineRows[row % 2];
    const start = row < 2 ? 0 : this.cols;
    return line + ((((start + col - this.shift) % lineLength) + lineLength) % lineLength);
  }

  /// What the display shows: one string per row. Characters outside printable ASCII show as {xx} (hex).
  screen() {
    const rows = [];
    for (let row = 0; row < this.rows; row++) {
      let text = '';
      for (let col = 0; col < this.cols; col++) {
        const c = this.ddram[this.shownAddress(row, col)];
        text += c >= 0x20 && c < 0x7f ? String.fromCharCode(c) : `{${c.toString(16).padStart(2, '0')}}`;
      }
      rows.push(text);
    }
    return rows;
  }

  /// The cursor's row and column on the screen, or null when it is outside the visible window (or in CGRAM).
  cursor() {
    if (this.cgram) return null;
    for (let row = 0; row < this.rows; row++) {
      for (let col = 0; col < this.cols; col++) {
        if (this.shownAddress(row, col) === this.address) return [row, col];
      }
    }
    return null;
  }

  violation(cycle, text) {
    this.violations++;
    this.log.push(`${cycle} violation ${text}`);
  }

  us(cycles) {
    return (cycles / this.cyclesPerUs).toFixed(1);
  }

  /// The instruction and violation lines, then the final state.
  report() {
    const on = (b) => (b ? 'on' : 'off');
    const cursor = this.cursor();
    return [
      ...this.log,
      ...this.screen().map((text, row) => `screen ${row} |${text}|`),
      `display ${on(this.displayOn)} cursor ${on(this.cursorOn)} blink ${on(this.blinkOn)}`,
      `cursor ${cursor === null ? 'hidden' : `row ${cursor[0]} col ${cursor[1]}`}`,
      `mode ${this.eightBit ? 8 : 4}-bit lines ${this.twoLine ? 2 : 1} shift ${this.shift}`,
      `first instruction at ${
        this.firstInstructionAt === null ? 'none' : (this.firstInstructionAt / this.cyclesPerUs / 1000).toFixed(3)
      } ms`,
      `violations ${this.violations}`,
    ];
  }
}
