# Installing unodar

## What you need

- **A Dart SDK, 3.13 or later.** If you have Flutter, its Dart works: `dart --version` shows the version. Otherwise
  install Dart from <https://dart.dev/get-dart>. unodar installs no Dart and no Flutter.
- **macOS or Linux.** Windows is untested in v0.7: `unodar setup` has no Windows download, so there you would need
  to install arduino-cli yourself (see "Using your own arduino-cli" below).
- **An Arduino Uno**, genuine or a clone, and a USB cable that carries data. To try without a board, see
  [Wokwi](https://wokwi.com) in [`FIRST_PROGRAM.md`](FIRST_PROGRAM.md).

## Install

```sh
dart pub global activate --source git https://github.com/TheCodeDaniel/unodar \
  --git-path packages/unodar_compiler --git-ref v0.7.0
unodar setup
```

The first command installs the `unodar` command from the v0.7.0 release. Pub puts it in `~/.pub-cache/bin`; if
your shell does not find `unodar` afterwards, add that folder to your `PATH` (pub prints the line to add, e.g.
`export PATH="$PATH":"$HOME/.pub-cache/bin"` in `~/.zshrc` or `~/.bashrc`).

`unodar setup` installs the Arduino toolchain unodar is tested with, exactly these versions:

| What | Version | Size |
|---|---|---|
| arduino-cli (downloaded from its GitHub release, SHA-256 checked) | 1.5.1 | 34 MB |
| The `arduino:avr` core, with its compiler (avr-gcc) and uploader (avrdude) | 1.8.8 | 327 MB |
| Libraries Servo, LiquidCrystal, DHT sensor library, Adafruit Unified Sensor | 1.3.0, 1.0.7, 1.4.7, 1.1.15 | < 1 MB |
| arduino-cli's download cache | | 73 MB |

Measured on an Apple Silicon Mac on a home connection: **93 s, 435 MB**. Everything goes into `~/.unodar` (set
`UNODAR_HOME` to use another folder). Nothing else changes: not `~/.arduino15`, not `~/Arduino`, no `sudo`.
`setup` is safe to run again: it installs only what is missing, and ends with the same report as `unodar doctor`.

On an **Apple Silicon Mac**, the `arduino:avr` compiler is built for Intel Macs and runs under Rosetta 2. If
`unodar doctor` says it is missing, install it with `softwareupdate --install-rosetta --agree-to-license`.

On **Linux**, uploading needs permission to open the board's serial port: `sudo usermod -aG dialout $USER`, then log
out and in again (`unodar doctor` checks it).

## Behind a proxy

Both the download of arduino-cli and arduino-cli itself honour `HTTPS_PROXY` (and `HTTP_PROXY`):

```sh
HTTPS_PROXY=http://proxy.example:3128 unodar setup
```

## Using your own arduino-cli

If `~/.unodar` has no toolchain, unodar uses an `arduino-cli` on your `PATH`, but only if it has exactly the core and
libraries above (`unodar doctor` lists what differs; any arduino-cli version is accepted there). The managed copy is
always preferred, so `unodar setup` is the simple way.

## Updating

Install the compiler of the new version with the first command and its new `--git-ref`, run `unodar setup` again,
and change the `ref:` of `unodar` in each project's `pubspec.yaml` to the same version (then `dart pub get`). The
compiler and a project's `package:unodar` must be the same version: `unodar build` says so if they are not.

## Uninstalling

```sh
rm -rf ~/.unodar
dart pub global deactivate unodar_compiler
```
