#!/usr/bin/env node
// Runs an ATmega328P program (the .hex arduino-cli builds) in avr8js and prints what it sends on the USART.
//
//   node tool/avr_runner/run.mjs <program.hex> [--cycles N] [--until TEXT] [--adc CHANNEL=VOLTS]...
//                                [--pin PIN=LEVEL@MS]... [--pin-log FILE] [--pin-log-cycles]
//                                [--eeprom FILE] [--eeprom-writes FILE] [--spi-reply HEX] [--spi-log FILE]
//                                [--lcd RS,E,D4,D5,D6,D7 [--lcd-size COLSxROWS] --lcd-log FILE]
//                                [--dht PIN [--dht-reading TEMP,HUM@MS]... [--dht-bad-checksum] [--dht-one-us US]
//                                 --dht-log FILE]
//
// The CPU runs at 16 MHz with timers 0-2, USART0, the ADC and GPIO ports B, C and D, which is what the Arduino
// core needs for millis(), micros(), delay(), analogRead(), digitalRead/Write() and Serial. It stops after N cycles
// (default 32 000 000, two simulated seconds) or as soon as the output contains TEXT. stdout is exactly the bytes
// the program transmitted; a summary goes to stderr. Exit status: 0 when stopped by --until (or by the cycle limit
// if no --until was given), 1 when the cycle limit was reached first, 2 on a usage or input error.
//
// Pins (D0-D13, A0-A5) are wired like a breadboard: `--pin D2=low@100` drives D2 LOW from 100 ms of simulated time
// on (a pressed button to GND), `high` drives it HIGH, and `open` stops driving it (a released button). MS may have
// decimals, so contact bounce can be scheduled. A pin nobody drives reads HIGH when its internal pull-up is on
// (INPUT_PULLUP) and LOW otherwise; an output pin reads its own level. avr8js models the registers but not the
// pull-up, so the runner computes each input level whenever the program writes a port.
//
// --pin-log FILE records every change of every pin's state as `<ms> <pin> <state>` lines, ms with three decimals
// (microsecond resolution) and state one of `low`, `high` (output levels), `input`, `input-pullup`. With
// --pin-log-cycles the first column is the CPU cycle instead (62.5 ns), for bit-level protocols.
//
// --eeprom FILE gives the program a 1024-byte EEPROM (avr8js AVREEPROM) loaded from FILE, or erased (0xFF) when FILE
// does not exist, and saved back to FILE when the run ends, so a second run sees what the first wrote (a reset).
// --eeprom-writes FILE writes the number of byte programming operations of the run (an erase-and-write counts once).
//
// --spi-reply HEX is a scripted SPI slave: each byte the program transfers as master gets the next byte of HEX back
// (`a5ff01`), then 0xFF. --spi-log FILE records each transfer as `<cycle> <sent> <received> mode=<0-3>
// order=<msbFirst|lsbFirst> divider=<n>`, hex bytes, the settings read from SPCR/SPSR at that moment.
//
// --lcd RS,E,D4,D5,D6,D7 connects an HD44780 character LCD in 4-bit mode to those pins (e.g. D12,D11,D5,D4,D3,D2;
// R/W tied to GND), a COLSxROWS display (default 16x2). --lcd-log FILE records each instruction it executes as
// `<cycle> cmd8|cmd|data 0x..`, each timing violation as `<cycle> violation <text>`, and then the final state:
// `screen <row> |<text>|` per row, the display/cursor/blink flags, the cursor position, the mode and the number of
// violations (see hd44780.mjs).
//
// --dht PIN connects a DHT22 temperature and humidity sensor to PIN's data line (open-drain, with the pin's pull-up).
// --dht-reading TEMP,HUM@MS is what it measures from MS on (default 21.5,48.2@0; repeat it for a schedule).
// --dht-bad-checksum sends every frame with a wrong checksum; --dht-one-us US sends 1 bits US us long instead of 70
// (a negative control). --dht-log FILE records each answered start signal as `<ms> start <low> ms, sent T=… H=…
// frame=<hex>`, each violation as `<ms> violation <text>`, then `violations <n>` (see dht22.mjs).
//
// unodar's runtime fidelity harness (packages/unodar_compiler/test/runtime_fidelity_test.dart) prints one
// PASS/FAIL line per check and a final DONE line, and runs this with --until DONE.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import {
  AVRADC,
  AVRTimer,
  AVRIOPort,
  AVRUSART,
  AVREEPROM,
  AVRSPI,
  CPU,
  EEPROMMemoryBackend,
  PinState,
  adcConfig,
  avrInstruction,
  portBConfig,
  portCConfig,
  portDConfig,
  eepromConfig,
  spiConfig,
  timer0Config,
  timer1Config,
  timer2Config,
  usart0Config,
} from 'avr8js';
import { Dht22 } from './dht22.mjs';
import { Hd44780 } from './hd44780.mjs';

const clockHz = 16_000_000;
const cyclesPerMs = clockHz / 1000;
const flashBytes = 0x8000;

/// Arduino pin name -> [port, bit] on the Uno (variants/standard/pins_arduino.h).
function pinPosition(name) {
  const digital = /^D([0-9]|1[0-3])$/.exec(name);
  const analog = /^A([0-5])$/.exec(name);
  if (digital) {
    const n = Number(digital[1]);
    return n < 8 ? ['D', n] : ['B', n - 8];
  }
  if (analog) return ['C', Number(analog[1])];
  return null;
}

function fail(message) {
  process.stderr.write(`avr_runner: ${message}\n`);
  process.exit(2);
}

function parseArguments(argv) {
  const options = {
    hex: null,
    cycles: 32_000_000,
    until: null,
    adc: [],
    pins: [],
    pinLog: null,
    pinLogCycles: false,
    eeprom: null,
    eepromWrites: null,
    spiReply: null,
    spiLog: null,
    lcd: null,
    lcdSize: [16, 2],
    lcdLog: null,
    dht: null,
    dhtReadings: [],
    dhtBadChecksum: false,
    dhtOneUs: 70,
    dhtLog: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = () => argv[++i] ?? fail(`${arg} needs a value`);
    if (arg === '--cycles') options.cycles = Number(value());
    else if (arg === '--until') options.until = value();
    else if (arg === '--adc') {
      const match = /^A?([0-7])=([0-9.]+)$/.exec(value());
      if (!match) fail('--adc takes CHANNEL=VOLTS, e.g. A0=2.5');
      options.adc.push([Number(match[1]), Number(match[2])]);
    } else if (arg === '--pin') {
      const match = /^([DA][0-9]+)=(low|high|open)@([0-9]+(?:\.[0-9]+)?)$/.exec(value());
      if (!match || !pinPosition(match[1])) {
        fail('--pin takes PIN=LEVEL@MS, PIN one of D0-D13 and A0-A5, LEVEL one of low, high and open');
      }
      options.pins.push({ pin: match[1], level: match[2], cycle: Math.round(Number(match[3]) * cyclesPerMs) });
    } else if (arg === '--pin-log') options.pinLog = value();
    else if (arg === '--pin-log-cycles') options.pinLogCycles = true;
    else if (arg === '--eeprom') options.eeprom = value();
    else if (arg === '--eeprom-writes') options.eepromWrites = value();
    else if (arg === '--spi-reply') {
      const hex = value();
      if (!/^([0-9a-fA-F]{2})*$/.test(hex)) fail('--spi-reply takes bytes in hex, e.g. a5ff01');
      options.spiReply = Buffer.from(hex, 'hex');
    } else if (arg === '--spi-log') options.spiLog = value();
    else if (arg === '--lcd') {
      const pins = value().split(',');
      if (pins.length !== 6 || !pins.every(pinPosition) || new Set(pins).size !== 6) {
        fail('--lcd takes six different pins RS,E,D4,D5,D6,D7, e.g. D12,D11,D5,D4,D3,D2');
      }
      options.lcd = pins;
    } else if (arg === '--lcd-size') {
      const match = /^([0-9]+)x([1-4])$/.exec(value());
      if (!match) fail('--lcd-size takes COLSxROWS, e.g. 16x2');
      options.lcdSize = [Number(match[1]), Number(match[2])];
    } else if (arg === '--lcd-log') options.lcdLog = value();
    else if (arg === '--dht') {
      options.dht = value();
      if (!pinPosition(options.dht)) fail('--dht takes a pin, one of D0-D13 and A0-A5');
    } else if (arg === '--dht-reading') {
      const match = /^(-?[0-9]+(?:\.[0-9])?),([0-9]+(?:\.[0-9])?)@([0-9]+(?:\.[0-9]+)?)$/.exec(value());
      if (!match) fail('--dht-reading takes TEMP,HUM@MS with at most one decimal, e.g. 21.5,48.2@0');
      options.dhtReadings.push({
        temperature: Number(match[1]),
        humidity: Number(match[2]),
        at: Math.round(Number(match[3]) * cyclesPerMs),
      });
    } else if (arg === '--dht-bad-checksum') options.dhtBadChecksum = true;
    else if (arg === '--dht-one-us') options.dhtOneUs = Number(value());
    else if (arg === '--dht-log') options.dhtLog = value();
    else if (arg.startsWith('--')) fail(`unknown option ${arg}`);
    else options.hex = arg;
  }
  if (!options.hex) {
    fail(
      'usage: run.mjs <program.hex> [--cycles N] [--until TEXT] [--adc CHANNEL=VOLTS]... [--pin PIN=LEVEL@MS]... ' +
        '[--pin-log FILE] [--pin-log-cycles] [--eeprom FILE] [--eeprom-writes FILE] [--spi-reply HEX] [--spi-log FILE] ' +
        '[--lcd RS,E,D4,D5,D6,D7 [--lcd-size COLSxROWS] --lcd-log FILE] ' +
        '[--dht PIN [--dht-reading TEMP,HUM@MS]... [--dht-bad-checksum] [--dht-one-us US] --dht-log FILE]',
    );
  }
  if (!Number.isSafeInteger(options.cycles) || options.cycles <= 0) fail('--cycles must be a positive integer');
  if ((options.lcd === null) !== (options.lcdLog === null)) fail('--lcd and --lcd-log go together');
  if ((options.dht === null) !== (options.dhtLog === null)) fail('--dht and --dht-log go together');
  if (options.dhtReadings.length === 0) options.dhtReadings.push({ temperature: 21.5, humidity: 48.2, at: 0 });
  options.dhtReadings.sort((a, b) => a.at - b.at);
  return options;
}

/// Intel HEX (record types 00 data, 01 end of file; avr-gcc output for a 32 KB part needs no others).
function loadHex(path) {
  const bytes = new Uint8Array(flashBytes);
  for (const [index, raw] of readFileSync(path, 'utf8').split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (line === '') continue;
    if (!line.startsWith(':')) fail(`${path}:${index + 1}: not an Intel HEX record`);
    const record = Buffer.from(line.slice(1), 'hex');
    const [count, high, low, type] = record;
    const checksum = record.reduce((sum, b) => (sum + b) & 0xff, 0);
    if (record.length !== count + 5 || checksum !== 0) fail(`${path}:${index + 1}: bad record`);
    if (type === 0x01) break;
    if (type !== 0x00) fail(`${path}:${index + 1}: unsupported record type ${type}`);
    const address = (high << 8) | low;
    if (address + count > flashBytes) fail(`${path}:${index + 1}: data beyond 32 KB of flash`);
    bytes.set(record.subarray(4, 4 + count), address);
  }
  return new Uint16Array(bytes.buffer);
}

const options = parseArguments(process.argv.slice(2));
const cpu = new CPU(loadHex(options.hex));
new AVRTimer(cpu, timer0Config);
new AVRTimer(cpu, timer1Config);
new AVRTimer(cpu, timer2Config);
const adc = new AVRADC(cpu, adcConfig);
for (const [channel, volts] of options.adc) adc.channelValues[channel] = volts;
const usart = new AVRUSART(cpu, usart0Config, clockHz);

// GPIO: what each pin is externally driven to ('low', 'high', or absent = open), and the state log.
const ports = {
  B: new AVRIOPort(cpu, portBConfig),
  C: new AVRIOPort(cpu, portCConfig),
  D: new AVRIOPort(cpu, portDConfig),
};
const pinNames = { B: [], C: [], D: [] };
for (let n = 0; n <= 13; n++) {
  const [port, bit] = pinPosition(`D${n}`);
  pinNames[port][bit] = `D${n}`;
}
for (let n = 0; n <= 5; n++) pinNames.C[n] = `A${n}`;
const driven = new Map();
const stateNames = {
  [PinState.Low]: 'low',
  [PinState.High]: 'high',
  [PinState.Input]: 'input',
  [PinState.InputPullUp]: 'input-pullup',
};
const lastStates = new Map();
const pinLog = [];

// The LCD, if connected: pin name -> its role.
const lcd = options.lcd === null ? null : new Hd44780({ clockHz, cols: options.lcdSize[0], rows: options.lcdSize[1] });
const lcdRoles = new Map((options.lcd ?? []).map((pin, i) => [pin, ['rs', 'e', 'd4', 'd5', 'd6', 'd7'][i]]));

// The DHT22, if connected: it pulls its pin low or lets it go, between the MCU's own changes.
const dht =
  options.dht === null
    ? null
    : new Dht22({
        clockHz,
        readings: options.dhtReadings,
        badChecksum: options.dhtBadChecksum,
        oneUs: options.dhtOneUs,
        drive: (low) => {
          if (low) driven.set(options.dht, 'low');
          else driven.delete(options.dht);
          updatePort(pinPosition(options.dht)[0]);
        },
      });

/// Recomputes the input level of every pin of `port` (driven, pulled up, or LOW) and logs state changes.
function updatePort(portName) {
  const port = ports[portName];
  for (let bit = 0; bit < 8; bit++) {
    const name = pinNames[portName][bit];
    if (!name) continue;
    const state = port.pinState(bit);
    const drive = driven.get(name);
    port.setPin(bit, drive !== undefined ? drive === 'high' : state === PinState.InputPullUp);
    if (lastStates.get(name) !== state) {
      const at = options.pinLogCycles ? `${cpu.cycles}` : (cpu.cycles / cyclesPerMs).toFixed(3);
      if (lastStates.has(name)) pinLog.push(`${at} ${name} ${stateNames[state]}`);
      lastStates.set(name, state);
      if (lcd !== null && lcdRoles.has(name)) lcd.pin(lcdRoles.get(name), state === PinState.High, cpu.cycles);
      if (dht !== null && name === options.dht) {
        for (const [delay, event] of dht.mcuPin(stateNames[state], cpu.cycles)) cpu.addClockEvent(event, delay);
      }
    }
  }
}
for (const portName of Object.keys(ports)) {
  ports[portName].addListener(() => updatePort(portName));
  updatePort(portName);
}

// EEPROM: a file-backed 1 KB array, counting programming operations.
const eepromBytes = 1024;
let eepromWrites = 0;
let eepromBackend = null;
if (options.eeprom !== null || options.eepromWrites !== null) {
  eepromBackend = new EEPROMMemoryBackend(eepromBytes);
  if (options.eeprom !== null && existsSync(options.eeprom)) {
    const saved = readFileSync(options.eeprom);
    if (saved.length !== eepromBytes) fail(`${options.eeprom}: an EEPROM file has ${eepromBytes} bytes`);
    eepromBackend.memory.set(saved);
  } else {
    eepromBackend.memory.fill(0xff);
  }
  const write = eepromBackend.writeMemory.bind(eepromBackend);
  eepromBackend.writeMemory = (address, value) => {
    eepromWrites++;
    write(address, value);
  };
  new AVREEPROM(cpu, eepromBackend, eepromConfig);
}

// SPI: a scripted slave that answers each byte after the transfer time the SPI clock gives.
const spiLog = [];
if (options.spiReply !== null || options.spiLog !== null) {
  const spi = new AVRSPI(cpu, spiConfig, clockHz);
  let next = 0;
  // The standard SPI mode is CPOL * 2 + CPHA (SPCR bits 3 and 2; SPI_MODE1 is CPHA only). avr8js 0.21.1's `spiMode`
  // swaps the two (it returns 2 for SPI_MODE1), so the mode is read from SPCR here.
  const spiMode = () => (cpu.data[spiConfig.SPCR] & 0x08 ? 2 : 0) | (cpu.data[spiConfig.SPCR] & 0x04 ? 1 : 0);
  spi.onByte = (sent) => {
    const reply = options.spiReply !== null && next < options.spiReply.length ? options.spiReply[next++] : 0xff;
    const hex = (b) => b.toString(16).padStart(2, '0');
    spiLog.push(
      `${cpu.cycles} ${hex(sent)} ${hex(reply)} mode=${spiMode()} order=${spi.dataOrder} divider=${spi.clockDivider}`,
    );
    cpu.addClockEvent(() => spi.completeTransfer(reply), spi.transferCycles);
  };
}

const schedule = [...options.pins].sort((a, b) => a.cycle - b.cycle);
let nextInput = 0;
function applyInputs() {
  while (nextInput < schedule.length && schedule[nextInput].cycle <= cpu.cycles) {
    const { pin, level } = schedule[nextInput++];
    if (level === 'open') driven.delete(pin);
    else driven.set(pin, level);
    updatePort(pinPosition(pin)[0]);
  }
}

let output = '';
usart.onByteTransmit = (byte) => {
  const text = String.fromCharCode(byte);
  output += text;
  process.stdout.write(text);
};

let stoppedByUntil = false;
while (cpu.cycles < options.cycles) {
  if (nextInput < schedule.length) applyInputs();
  avrInstruction(cpu);
  cpu.tick();
  if (options.until !== null && output.includes(options.until)) {
    stoppedByUntil = true;
    break;
  }
}
const reason = stoppedByUntil ? `found ${JSON.stringify(options.until)}` : 'cycle limit';
if (options.pinLog !== null) writeFileSync(options.pinLog, pinLog.map((line) => `${line}\n`).join(''));
if (options.eeprom !== null) writeFileSync(options.eeprom, eepromBackend.memory);
if (options.eepromWrites !== null) writeFileSync(options.eepromWrites, `${eepromWrites}\n`);
if (options.lcdLog !== null) writeFileSync(options.lcdLog, lcd.report().map((line) => `${line}\n`).join(''));
if (options.dhtLog !== null) writeFileSync(options.dhtLog, dht.report().map((line) => `${line}\n`).join(''));
if (options.spiLog !== null) writeFileSync(options.spiLog, spiLog.map((line) => `${line}\n`).join(''));
process.stderr.write(`avr_runner: stopped after ${cpu.cycles} cycles (${reason})\n`);
process.exitCode = options.until !== null && !stoppedByUntil ? 1 : 0;
