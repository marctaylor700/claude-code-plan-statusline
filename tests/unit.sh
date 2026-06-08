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

# Sourcing must define functions WITHOUT rendering (no stdout side-effect).
# The unguarded script renders during source; the guard prevents that.
out=$(source ./statusline.sh </dev/null)
[[ -z "$out" ]] && ok "source: no render side-effect" || bad "source: no render side-effect (got: $out)"

# Source in the parent shell so functions are visible to the checks below.
source ./statusline.sh </dev/null

# After sourcing, helper functions exist.
declare -F render_default >/dev/null && ok "source: functions defined" \
  || bad "source: functions defined"

echo
if (( fails )); then echo "unit: $fails FAILED"; exit 1; fi
echo "All unit tests passed."
