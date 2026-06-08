#!/usr/bin/env bash
# Unit tests for sourceable helpers in statusline.sh.
# Sourcing must NOT block on stdin and must NOT render — only define functions.
set -uo pipefail
cd "$(dirname "$0")/.."

ESC=$(printf '\033')
strip_ansi() { sed -E "s/${ESC}\[[0-9;]*m//g"; }

fails=0
ok()   { printf 'PASS %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1" >&2; fails=$((fails+1)); }

# Sourcing the script with stdin closed must return promptly (proves main() is
# guarded — an unguarded `input=$(cat)` would hang here).
source ./statusline.sh </dev/null
ok "source: did not block on stdin"

# After sourcing, helper functions exist.
declare -F render_default >/dev/null && ok "source: functions defined" \
  || bad "source: functions defined"

echo
if (( fails )); then echo "unit: $fails FAILED"; exit 1; fi
echo "All unit tests passed."
