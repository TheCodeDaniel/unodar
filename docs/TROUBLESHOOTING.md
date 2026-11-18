# Troubleshooting

Start with `unodar doctor`. It checks the toolchain, the project and the board, and prints the command that fixes
each problem (`✗` problem, `!` warning, `·` information). Every `unodar` command ends with one of these exit codes:

| Exit code | Meaning | Section |
|---|---|---|
| 0 | It worked. | |
| 1 | A problem in your Dart (the message says where and what to write instead). | [Errors in your program](#errors-in-your-program) |
| 2 | Bad usage, a file that cannot be read or written, or a bug in unodar. | [A bug in unodar](#a-bug-in-unodar) |
| 3 | The toolchain is missing, the wrong version, or cannot run. | [The toolchain](#the-toolchain) |
| 4 | The board: none found, several found, the port busy or not permitted, the upload failed. | [The board](#the-board) |

## Installing

**`unodar: command not found` after `dart pub global activate`.** Pub installed it in `~/.pub-cache/bin`, which is
not on your `PATH`. Add it (`export PATH="$PATH":"$HOME/.pub-cache/bin"` in `~/.zshrc` or `~/.bashrc`) and open a
new terminal.

**`dart pub global activate` fails to resolve versions.** Your Dart is older than 3.13. `dart --version` shows it;
upgrade Dart (or Flutter, if your `dart` comes from it).

## The toolchain

**`unodar setup` cannot download.** Check your connection; behind a proxy set `HTTPS_PROXY` (see
[`INSTALL.md`](INSTALL.md#behind-a-proxy)) and run `unodar setup` again: it continues where it stopped.

**"the download … has the wrong SHA-256".** The file that arrived is not the arduino-cli release unodar pinned, so it
was not installed. Run `unodar setup` again; if it repeats, something between you and GitHub changes downloads, and
it is worth reporting.

**"no arduino-cli download for windows_x64".** Windows is untested in v0.7. Install arduino-cli yourself and the
core and libraries that `unodar doctor` lists; unodar then uses the arduino-cli on your `PATH`.

**"avr-gcc is built for Intel Macs and needs Rosetta 2".** Run `softwareupdate --install-rosetta --agree-to-license`.

**An arduino-cli you installed yourself is "not used".** That is information, not a problem: unodar prefers its own
copy in `~/.unodar`, so your Arduino IDE or other projects are never affected.

**"this project uses package:unodar 0.6.0, but this compiler is unodar 0.7.0".** The compiler and the project's
`package:unodar` must be the same version. Change the `ref:` of `unodar` in `pubspec.yaml` and run `dart pub get`,
or install the compiler of the project's version (the message gives both commands).

## The board

**"No Arduino Uno found."** In order:
1. The cable: many USB cables only charge. Try another one; the board's power LED being on proves nothing.
2. A clone: boards with a CH340 (or CH341, FTDI, CP2102) USB chip cannot be identified as an Uno, so `flash` lists
   them as probable clones and prints the `unodar flash --port …` line to use. It never picks one by itself, because
   writing to the wrong device (a GPS, a 3D printer) is worse than one more flag. On older macOS versions a CH340
   needs its driver from the chip maker.
3. Linux: `unodar doctor` warns if you are not in the `dialout` group.
4. `unodar doctor` lists the Unos it sees on its `boards:` line.

**"2 Arduino Unos are plugged in".** Choose one with the `--port` line printed for it.

**"the port … is busy".** A serial monitor, the Arduino IDE or another program has the port open. Close it and flash
again.

**"you may not open …" (permission denied).** On Linux: `sudo usermod -aG dialout $USER`, then log out and in.

**"the board … did not answer"** (avrdude: "not in sync", "programmer is not responding"). The board on that port is
not an Uno with its bootloader (a Nano with the old bootloader, a Mega, or a board whose bootloader was erased), or
something wired to pins 0 and 1 disturbs the upload. Unplug what is on pins 0/1 and try again.

**The upload works but nothing happens.** Check the wiring against the pins in your program (a button between the
pin and **GND**; an LED with a resistor, the long leg towards the pin). Print from a callback with `Serial.println`
and watch it with a serial monitor (see [`FIRST_PROGRAM.md`](FIRST_PROGRAM.md#3-read-an-error)).

**It works in Wokwi but not on the board.** wokwi.com builds without unodar's `-fwrapv` flag, which only matters for
programs whose `int`s overflow; more often the difference is wiring, power, or a clone that needs `--port`.

## Errors in your program

Each error has a code, the line, and what to write instead; [`DIAGNOSTICS.md`](DIAGNOSTICS.md) has a page per code
with an example. The usual surprises for a Flutter developer: there is no `print` (use `Serial.println`), no
`setState` (use a `Signal`), no `async`/`Future` (use `Every`), no `String` variables, no lists, no Flutter imports,
and no `StatelessWidget`. The reason is the board: 2 KB of RAM, no heap and no event loop.

`--plain` prints errors without the source line, link and colour, for editors and scripts.

## A bug in unodar

"internal error" or "the C++ that unodar generated does not compile" is unodar's fault, not yours (exit 2). Please
report it at <https://github.com/TheCodeDaniel/unodar/issues> with your `main.dart`, the output, and the sketch folder
the message names. If your program contains `cpp('…')` or a binding of your own, a C++ error is more likely in that
code (exit 1), and the error's location points at your Dart line.
