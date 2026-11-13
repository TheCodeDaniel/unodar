#!/usr/bin/env node
// Runs an ATmega328P program (the .hex arduino-cli builds) in avr8js and prints what it sends on the USART.
//
//   node tool/avr_runner/run.mjs <program.hex> [--cycles N] [--until TEXT] [--adc CHANNEL=VOLTS]...
//
// The CPU runs at 16 MHz with timers 0-2, USART0 and the ADC, which is what the Arduino core needs for millis(),
// micros(), delay(), analogRead() and Serial. It stops after N cycles (default 32 000 000, two simulated seconds)
// or as soon as the output contains TEXT. stdout is exactly the bytes the program transmitted; a summary goes to
// stderr. Exit status: 0 when stopped by --until (or by the cycle limit if no --until was given), 1 when the cycle
// limit was reached first, 2 on a usage or input error.
//
// unodar's runtime fidelity harness (packages/unodar_compiler/test/runtime_fidelity_test.dart) prints one
// PASS/FAIL line per check and a final DONE line, and runs this with --until DONE.
import { readFileSync } from 'node:fs';
import {
  AVRADC,
  AVRTimer,
  AVRUSART,
  CPU,
  adcConfig,
  avrInstruction,
  timer0Config,
  timer1Config,
  timer2Config,
  usart0Config,
} from 'avr8js';

const clockHz = 16_000_000;
const flashBytes = 0x8000;

function fail(message) {
  process.stderr.write(`avr_runner: ${message}\n`);
  process.exit(2);
}

function parseArguments(argv) {
  const options = { hex: null, cycles: 32_000_000, until: null, adc: [] };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = () => argv[++i] ?? fail(`${arg} needs a value`);
    if (arg === '--cycles') options.cycles = Number(value());
    else if (arg === '--until') options.until = value();
    else if (arg === '--adc') {
      const match = /^A?([0-7])=([0-9.]+)$/.exec(value());
      if (!match) fail('--adc takes CHANNEL=VOLTS, e.g. A0=2.5');
      options.adc.push([Number(match[1]), Number(match[2])]);
    } else if (arg.startsWith('--')) fail(`unknown option ${arg}`);
    else options.hex = arg;
  }
  if (!options.hex) fail('usage: run.mjs <program.hex> [--cycles N] [--until TEXT] [--adc CHANNEL=VOLTS]...');
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

let output = '';
usart.onByteTransmit = (byte) => {
  const text = String.fromCharCode(byte);
  output += text;
  process.stdout.write(text);
};

let stoppedByUntil = false;
while (cpu.cycles < options.cycles) {
  avrInstruction(cpu);
  cpu.tick();
  if (options.until !== null && output.includes(options.until)) {
    stoppedByUntil = true;
    break;
  }
}
const reason = stoppedByUntil ? `found ${JSON.stringify(options.until)}` : 'cycle limit';
process.stderr.write(`avr_runner: stopped after ${cpu.cycles} cycles (${reason})\n`);
process.exitCode = options.until !== null && !stoppedByUntil ? 1 : 0;
