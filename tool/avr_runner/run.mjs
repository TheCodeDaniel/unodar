#!/usr/bin/env node
// Runs an ATmega328P program (the .hex arduino-cli builds) in avr8js and prints what it sends on the USART.
//
//   node tool/avr_runner/run.mjs <program.hex> [--cycles N] [--until TEXT] [--adc CHANNEL=VOLTS]...
//                                [--pin PIN=LEVEL@MS]... [--pin-log FILE]
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
// (microsecond resolution) and state one of `low`, `high` (output levels), `input`, `input-pullup`.
//
// unodar's runtime fidelity harness (packages/unodar_compiler/test/runtime_fidelity_test.dart) prints one
// PASS/FAIL line per check and a final DONE line, and runs this with --until DONE.
import { readFileSync, writeFileSync } from 'node:fs';
import {
  AVRADC,
  AVRTimer,
  AVRIOPort,
  AVRUSART,
  CPU,
  PinState,
  adcConfig,
  avrInstruction,
  portBConfig,
  portCConfig,
  portDConfig,
  timer0Config,
  timer1Config,
  timer2Config,
  usart0Config,
} from 'avr8js';

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
  const options = { hex: null, cycles: 32_000_000, until: null, adc: [], pins: [], pinLog: null };
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
    else if (arg.startsWith('--')) fail(`unknown option ${arg}`);
    else options.hex = arg;
  }
  if (!options.hex) {
    fail(
      'usage: run.mjs <program.hex> [--cycles N] [--until TEXT] [--adc CHANNEL=VOLTS]... [--pin PIN=LEVEL@MS]... ' +
        '[--pin-log FILE]',
    );
  }
  if (!Number.isSafeInteger(options.cycles) || options.cycles <= 0) fail('--cycles must be a positive integer');
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
      if (lastStates.has(name)) pinLog.push(`${(cpu.cycles / cyclesPerMs).toFixed(3)} ${name} ${stateNames[state]}`);
      lastStates.set(name, state);
    }
  }
}
for (const portName of Object.keys(ports)) {
  ports[portName].addListener(() => updatePort(portName));
  updatePort(portName);
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
process.stderr.write(`avr_runner: stopped after ${cpu.cycles} cycles (${reason})\n`);
process.exitCode = options.until !== null && !stoppedByUntil ? 1 : 0;
