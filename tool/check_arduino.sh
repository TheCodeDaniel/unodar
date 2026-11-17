#!/usr/bin/env bash
# Builds every example with `unodar build`, which compiles the generated sketch with arduino-cli for the Uno (with
# -fwrapv) and prints its size. The toolchain is found as unodar finds it: the managed copy in ~/.unodar (install it
# with `dart run unodar_compiler:unodar setup`), else arduino-cli on PATH with the pinned core and libraries.
# Fails loudly (non-zero) if the toolchain is missing or any example does not build: it never skips.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
for example in blink pulse dial button_led counter thermostat; do
  echo "== examples/$example"
  dart run unodar_compiler:unodar build "examples/$example/main.dart" -o "$out/$example"
done
