#!/bin/sh
# Differential test: proves the Swift report logic still matches the QML service.
#
# It runs the real QML functions under node and the Swift implementation over
# the same fixtures, then diffs every derived figure. Run this after touching
# anything in Core/.
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$ROOT/.." && pwd)
WORK=${TMPDIR:-/tmp}/pomodoro-difftest.$$
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

command -v node >/dev/null || { echo "node is required for the reference run"; exit 1; }

echo "==> Building"
cd "$ROOT"
swift build -c release >/dev/null
BIN=$(swift build -c release --show-bin-path)/Pomodoro

IDLE_STATE='{"version":4,"phase":"focus","running":false,"endAt":0,
"remainingSeconds":1500,"completedFocus":0,"cycleDateKey":"","activeNote":"",
"phaseStartedAt":0,"phaseRunStartedAt":0,"phaseElapsedSeconds":0,
"phasePlannedSeconds":0,"phaseSegments":[],"phaseRang":false}'

status=0
for fixture in generated hostile; do
    dir="$WORK/$fixture"
    mkdir -p "$dir"
    printf '%s\n' "$IDLE_STATE" > "$dir/pomodoro.json"
    python3 "$REPO/tools/fixtures.py" "$fixture" "$dir"

    node "$REPO/tools/qml-reference.js" "$dir" "$WORK/$fixture-reference.json" >/dev/null
    POMODORO_DATA_DIR="$dir" "$BIN" --report-dump "$WORK/$fixture-swift.json" >/dev/null

    printf '%-10s ' "$fixture"
    python3 "$REPO/tools/compare-reports.py" \
        "$WORK/$fixture-reference.json" "$WORK/$fixture-swift.json" || status=1
done

exit $status
