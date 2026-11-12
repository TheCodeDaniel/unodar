#!/usr/bin/env bash
# Builds examples/blink, examples/pulse and examples/dial with unodar and compiles the result with arduino-cli for the Uno.
# Fails loudly (non-zero) if the toolchain is missing: it never skips.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v arduino-cli >/dev/null; then
  echo "error: arduino-cli is not on PATH. Install: brew install arduino-cli" >&2
  echo "       (other platforms: https://arduino.github.io/arduino-cli/latest/installation/)" >&2
  exit 2
fi
if ! arduino-cli core list | grep -q 'arduino:avr'; then
  echo "error: the arduino:avr core is missing. Install: arduino-cli core update-index && arduino-cli core install arduino:avr" >&2
  exit 2
fi

# Servo is not part of the core; the Servo golden and examples need it (docs/SUBSET.md "Servo").
if ! arduino-cli lib list | grep -qE '^Servo\s'; then
  echo "error: the Servo library is missing. Install: arduino-cli lib install Servo@1.3.0" >&2
  exit 2
fi

# Signed overflow must wrap (docs/SUBSET.md "Building"). Kept identical to UnoTarget.buildProperties by
# test/unit/build_properties_test.dart.
build_properties=(
  --build-property compiler.c.extra_flags=-fwrapv
  --build-property compiler.cpp.extra_flags=-fwrapv
  --build-property compiler.c.elf.extra_flags=-fwrapv
)

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
for example in blink pulse dial; do
  ino="$(dart run packages/unodar_compiler/bin/unodar.dart build "examples/$example/main.dart" -o "$out/$example")"
  echo "generated: $ino"
  arduino-cli compile --fqbn arduino:avr:uno "${build_properties[@]}" "$(dirname "$ino")"
done
