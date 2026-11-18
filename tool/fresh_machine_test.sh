#!/usr/bin/env bash
# Runs the README quick start as a stranger would, on an account with nothing but a Dart SDK: a fresh HOME (so a
# fresh pub cache and ~/.unodar), and a PATH with only the Dart SDK and the system directories (so no arduino-cli,
# Homebrew or Node from this machine is seen). Used by the fresh-machine CI jobs and on the maintainer's machine.
#
# The quick-start block is read from README.md (between the quickstart markers), so the test cannot drift from what
# the README says. Until the release tag exists, two lines are pointed at this checkout instead of GitHub (the
# default, --source local): the activate line installs the commit at HEAD of this clone, and `unodar new` depends on
# this checkout's packages/unodar. With --source github the block runs exactly as written (after the release).
#
# Besides the block it checks: `unodar doctor` exits 0 after setup; a second `unodar setup` installs nothing;
# nothing was written to ~/.arduino15 or ~/Arduino; `unodar flash` either uploads (a board is plugged in) or exits 4
# with "No Arduino Uno found". It prints how long each step took and, on macOS, the CPU type of the core's avr-gcc.
#
# Usage: tool/fresh_machine_test.sh [--source local|github] [--keep]
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source=local
keep=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source="${2:-}"; shift 2 ;;
    --keep) keep=1; shift ;;
    *) echo "usage: $0 [--source local|github] [--keep]" >&2; exit 2 ;;
  esac
done
[[ "$source" == local || "$source" == github ]] || { echo "error: --source is local or github" >&2; exit 2; }

dart_path="$(command -v dart || true)"
[[ -n "$dart_path" ]] || { echo "error: dart is not on PATH; install a Dart SDK (https://dart.dev/get-dart)" >&2; exit 2; }
sdk_bin="$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dart_path")")"

sandbox="$(mktemp -d)"
if [[ "$keep" == 0 ]]; then trap 'rm -rf "$sandbox"' EXIT; else echo "sandbox kept: $sandbox"; fi
export HOME="$sandbox/home"
mkdir -p "$HOME" "$sandbox/work"
export PATH="$sdk_bin:$HOME/.pub-cache/bin:/usr/bin:/bin:/usr/sbin:/sbin"
unset UNODAR_HOME PUB_CACHE
echo "== fresh account: HOME=$HOME"
echo "== PATH=$PATH"
command -v arduino-cli >/dev/null && { echo "error: arduino-cli is still visible on the clean PATH" >&2; exit 2; }
dart --version

block="$(awk '/<!-- quickstart -->/{on=1; next} /<!-- \/quickstart -->/{on=0} on' "$repo/README.md" | sed '/^```/d')"
[[ -n "$block" ]] || { echo "error: no quick-start block in README.md" >&2; exit 2; }
if [[ "$source" == local ]]; then
  if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    echo "warning: the checkout has uncommitted changes; the test installs the commit at HEAD, not the working tree"
  fi
  head="$(git -C "$repo" rev-parse HEAD)"
  block="${block//https:\/\/github.com\/TheCodeDaniel\/unodar/$repo}"
  block="$(sed -E "s/--git-ref v[0-9][^ ]*/--git-ref $head/" <<<"$block")"
  block="$(sed -E "s|^unodar new hello$|unodar new hello --unodar-path $repo/packages/unodar|" <<<"$block")"
fi
# The last line, `unodar flash`, may find no board (CI): checked separately below.
block="$(sed -E 's/^unodar flash$/unodar flash > flash.log 2>\&1 \&\& echo 0 > flash.exit || echo $? > flash.exit/' <<<"$block")"
echo "== the quick start, as run:"
echo "$block"

script="$sandbox/quickstart.sh"
{
  echo 'set -euo pipefail'
  echo 'step() { printf "\n== [%s s] %s\n" "$(( $(date +%s) - start ))" "$*"; }'
  echo 'start=$(date +%s)'
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # A line ending in a backslash continues on the next one: announce the command once.
    if [[ -n "${pending:-}" ]]; then pending="$pending"$'\n'"$line"; else pending="$line"; fi
    [[ "$line" == *\\ ]] && continue
    printf 'step %q\n%s\n' "${pending%%$'\n'*}" "$pending"
    pending=""
  done <<<"$block"
  echo 'step done'
} > "$script"

cd "$sandbox/work"
started=$(date +%s)
bash "$script"
project="$sandbox/work/hello"
echo
echo "== quick start finished in $(( $(date +%s) - started )) s"

echo "== unodar flash:"
cat "$project/flash.log"
flash_exit="$(cat "$project/flash.exit")"
if [[ "$flash_exit" == 0 ]]; then
  echo "ok: uploaded to a board"
elif [[ "$flash_exit" == 4 ]] && grep -q "No Arduino Uno found" "$project/flash.log"; then
  echo "ok: no board plugged in, exit 4 as documented"
else
  echo "error: unodar flash exited $flash_exit" >&2
  exit 1
fi
grep -q '^flash [0-9]* B of 32256' "$project/flash.log" || { echo "error: flash did not print the size line" >&2; exit 1; }

echo "== unodar doctor (in the project):"
(cd "$project" && unodar doctor)

echo "== a second unodar setup installs nothing:"
second="$(unodar setup)"
echo "$second" | grep -E '^(✓|Ready|unodar)' || true
grep -q 'arduino-cli .* (already installed)' <<<"$second" || { echo "error: setup reinstalled arduino-cli" >&2; exit 1; }
grep -q 'core .* (already installed)' <<<"$second" || { echo "error: setup reinstalled the core" >&2; exit 1; }
grep -q 'libraries .* (already installed)' <<<"$second" || { echo "error: setup reinstalled libraries" >&2; exit 1; }

echo "== nothing outside ~/.unodar:"
for dir in "$HOME/.arduino15" "$HOME/Arduino" "$HOME/Documents/Arduino" "$HOME/Library/Arduino15"; do
  [[ -e "$dir" ]] && { echo "error: $dir was created" >&2; exit 1; }
done
du -sh "$HOME/.unodar"

if [[ "$(uname)" == Darwin ]]; then
  echo "== the core's compiler on this Mac ($(uname -m)):"
  for tool in "$HOME"/.unodar/data/packages/arduino/tools/avr-gcc/*/bin/avr-gcc \
      "$HOME"/.unodar/data/packages/arduino/tools/avrdude/*/bin/avrdude; do
    file "$tool"
  done
  if [[ "$(uname -m)" == arm64 ]]; then
    if /usr/bin/pgrep -q oahd; then echo "Rosetta 2: installed"; else echo "Rosetta 2: not installed"; fi
  fi
fi
echo
echo "fresh-machine test passed"
