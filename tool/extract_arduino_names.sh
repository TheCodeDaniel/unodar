#!/usr/bin/env bash
# Prints every identifier the Arduino AVR core (Arduino.h and everything it includes) puts in the global scope that a
# unodar user name could collide with, one per line, sorted: lower/mixed-case macros, typedef names, global function
# names, class names, and extern objects. Names starting with `_` are left out (unodar never emits them for users).
#
# Used to generate packages/unodar_compiler/lib/src/emitter/arduino_avr_names.dart and, in
# test/reserved_names_test.dart, to check that the checked-in list still covers the installed core.
# Requires arduino-cli with the arduino:avr core; fails loudly otherwise. ARDUINO_CLI and ARDUINO_CLI_CONFIG select
# another arduino-cli and its configuration file (the test passes unodar's managed copy, ~/.unodar, when it is used).
set -euo pipefail
cli=("${ARDUINO_CLI:-arduino-cli}")
[[ -n "${ARDUINO_CLI_CONFIG:-}" ]] && cli+=(--config-file "$ARDUINO_CLI_CONFIG")
command -v "${cli[0]}" >/dev/null || { echo "error: arduino-cli not found; run \`unodar setup\`" >&2; exit 2; }
data="$("${cli[@]}" config get directories.data)"
core="$(ls -d "$data"/packages/arduino/hardware/avr/* 2>/dev/null | sort -V | tail -1)"
gxx="$(ls -d "$data"/packages/arduino/tools/avr-gcc/*/bin/avr-g++ 2>/dev/null | sort -V | tail -1)"
[[ -n "$core" && -x "$gxx" ]] || { echo "error: arduino:avr core missing (arduino-cli core install arduino:avr)" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo '#include <Arduino.h>' > "$tmp/a.cpp"
flags=(-mmcu=atmega328p -DF_CPU=16000000L -DARDUINO=10819 -DARDUINO_AVR_UNO -DARDUINO_ARCH_AVR
  -I"$core/cores/arduino" -I"$core/variants/standard" -x c++ -std=gnu++11 -w)
"$gxx" "${flags[@]}" -E -dM "$tmp/a.cpp" > "$tmp/macros"
"$gxx" "${flags[@]}" -E -P "$tmp/a.cpp" > "$tmp/pre"

{
  # Macros containing a lower-case letter (all-caps ones are covered by unodar's all-caps rule).
  awk '{print $2}' "$tmp/macros" | sed 's/(.*//' | grep '[a-z]'
  # typedef names.
  grep -oE 'typedef [^;{]*;' "$tmp/pre" | grep -oE '[A-Za-z_][A-Za-z0-9_]* *(\[[^]]*\])? *;$' | sed -E 's/ *(\[.*\])? *;//'
  # Functions declared at namespace scope (unindented declarations).
  grep -E '^(extern |static |inline |__inline__ )*[A-Za-z_][A-Za-z0-9_ ]*[ *][A-Za-z_][A-Za-z0-9_]* *\(' "$tmp/pre" \
    | sed -E 's/^([^(]*[ *])([A-Za-z_][A-Za-z0-9_]*) *\(.*/\2/'
  # Classes and structs, and extern objects such as `Serial`.
  grep -oE '^(class|struct) [A-Za-z_][A-Za-z0-9_]*' "$tmp/pre" | awk '{print $2}'
  grep -oE '^ *extern [A-Za-z_][A-Za-z0-9_ ]* [A-Za-z_][A-Za-z0-9_]*;' "$tmp/pre" | sed -E 's/.* ([A-Za-z_][A-Za-z0-9_]*);/\1/'
} | grep -v '^_' | grep -vxE 'int|const|setup|loop' | sort -u
