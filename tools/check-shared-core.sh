#!/usr/bin/env bash
# Enforce the invariant that makes one core serve three platforms.
#
# core/ must not branch on the operating system and must not reach a host API
# directly: every such difference belongs in the two Platform.qml files, whose
# contracts must stay identical.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

fail() { echo "FAIL: $*" >&2; FAILED=1; }

# 1. No host branching or host commands in the shared core.
while read -r pattern description; do
  hits="$(grep -rnE "$pattern" "$ROOT/core" || true)"
  if [[ -n "$hits" ]]; then
    fail "$description"
    echo "$hits" | sed 's/^/    /' >&2
  fi
done <<'PATTERNS'
Qt\.platform\.os core/ branches on the operating system
^[^i].*Quickshell\.(env|execDetached) core/ calls the Quickshell singleton directly
\b(xdg-open|pw-play|afplay|osascript|notify-send|omarchy-notification-send)\b core/ names a host command
%LOCALAPPDATA%|/usr/share/sounds|Library/Application core/ hardcodes a host path
PATTERNS

# 2. The two Platform.qml implementations must expose the same contract.
contract() {
  grep -oE "^    (readonly property [A-Za-z]+ [a-zA-Z]+|function [a-zA-Z]+)" "$1" |
    awk '{print $NF}' | sed 's/(.*//' | sort -u
}
QUICKSHELL_ONLY="$(comm -23 <(contract "$ROOT/platform/quickshell/Platform.qml") \
                            <(contract "$ROOT/platform/desktop/qml/Platform.qml"))"
DESKTOP_ONLY="$(comm -13 <(contract "$ROOT/platform/quickshell/Platform.qml") \
                         <(contract "$ROOT/platform/desktop/qml/Platform.qml"))"

# Members the core never touches are implementation detail, not contract.
for member in $QUICKSHELL_ONLY $DESKTOP_ONLY; do
  if grep -rqE "(platformSeam|\.platform)\.$member\b" "$ROOT/core"; then
    fail "Platform.qml implementations disagree on '$member', which core/ uses"
  fi
done

# 3. Everything the core does use must exist in both implementations.
for member in $(grep -rohE "(platformSeam|\.platform)\.[a-zA-Z]+" "$ROOT/core" |
                  sed 's/.*\.//' | sort -u); do
  for implementation in "$ROOT/platform/quickshell/Platform.qml" \
                        "$ROOT/platform/desktop/qml/Platform.qml"; do
    grep -qE "(property [A-Za-z]+ $member\b|function $member\()" "$implementation" ||
      fail "core/ uses platform.$member, missing from $(basename "$(dirname "$implementation")")/Platform.qml"
  done
done

[[ "$FAILED" == "0" ]] && echo "shared core is platform-neutral; Platform.qml contracts agree"
exit "$FAILED"
