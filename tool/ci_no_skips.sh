#!/usr/bin/env bash
# Fails if a `dart test --file-reporter json:<file>` run skipped any test. Used by CI, where every test must run:
# with UNODAR_REQUIRE_ARDUINO=1 the toolchain-gated tests already fail instead of skipping, and this catches any
# other skip.
set -euo pipefail
report="${1:?usage: tool/ci_no_skips.sh <dart test json report>}"
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }
[[ -s "$report" ]] || { echo "error: no test report at $report" >&2; exit 2; }
# testStart carries the name; testDone says whether it was skipped. Hidden entries are loading/setUpAll pseudo-tests.
skipped="$(jq -r -s '
  (map(select(.type == "testStart")) | map({key: (.test.id | tostring), value: .test.name}) | from_entries) as $names
  | .[] | select(.type == "testDone" and .skipped == true and .hidden == false) | $names[.testID | tostring]' "$report")"
total="$(jq -s '[.[] | select(.type == "testDone" and .hidden == false)] | length' "$report")"
if [[ -n "$skipped" ]]; then
  echo "error: tests were skipped, but CI requires every test to run:" >&2
  echo "$skipped" | sed 's/^/  - /' >&2
  exit 1
fi
echo "$total tests ran, none skipped."
