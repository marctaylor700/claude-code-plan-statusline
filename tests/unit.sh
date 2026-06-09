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

# now_ms returns integer milliseconds, sane magnitude (> year 2001 in ms).
ms=$(now_ms)
[[ "$ms" =~ ^[0-9]+$ ]] && ok "now_ms: integer ($ms)" || bad "now_ms: integer (got '$ms')"
(( ms > 1000000000000 )) && ok "now_ms: magnitude" || bad "now_ms: magnitude ($ms)"

# sweep must preserve the text exactly once ANSI is stripped (no dropped/dup
# chars), for any ramp. Set rate vars so limit_pegged works under `set -u`.
five_pct=''; week_pct=''
SWEEP_RAMP=( '' '38;5;252' '1;38;5;255' )   # default-style ramp
got=$(sweep 'Opus 4.8' | strip_ansi)
[[ "$got" == "Opus 4.8" ]] && ok "sweep: preserves text" || bad "sweep: preserves text (got '$got')"
[[ -z "$(sweep '')" ]] && ok "sweep: empty -> empty" || bad "sweep: empty -> empty"
[[ "$(sweep 'X' | strip_ansi)" == "X" ]] && ok "sweep: single char" || bad "sweep: single char"

SWEEP_RAMP=( '38;5;214' '38;5;221' '1;38;5;230' )   # non-empty base ramp
[[ "$(sweep 'Opus 4.8' | strip_ansi)" == "Opus 4.8" ]] && ok "sweep: non-empty base preserves text" || bad "sweep: non-empty base"

# Pegged: name freezes dim, still preserves text.
five_pct=100
[[ "$(sweep 'Opus 4.8' | strip_ansi)" == "Opus 4.8" ]] && ok "sweep: pegged preserves text" || bad "sweep: pegged"
five_pct=''

# ── theme loaders ────────────────────────────────────────────────────────────
theme_default
[[ "$LABEL_SEP" == ":" ]] && ok "theme_default: LABEL_SEP" || bad "theme_default: LABEL_SEP ('$LABEL_SEP')"
[[ "$SEG_CIRCLE" == "0" ]] && ok "theme_default: SEG_CIRCLE" || bad "theme_default: SEG_CIRCLE"
[[ ${#SWEEP_RAMP[@]} -eq 3 ]] && ok "theme_default: ramp len" || bad "theme_default: ramp len"

for t in hearth glow scrubs; do
  "theme_$t"
  [[ ${#SWEEP_RAMP[@]} -eq 3 ]] && ok "theme_$t: ramp len" || bad "theme_$t: ramp len"
  [[ "$LABEL_SEP" == "" ]]      && ok "theme_$t: LABEL_SEP empty" || bad "theme_$t: LABEL_SEP ('$LABEL_SEP')"
  [[ "$SEG_CIRCLE" == "1" ]]    && ok "theme_$t: SEG_CIRCLE" || bad "theme_$t: SEG_CIRCLE"
  [[ -n "$EGG_RESET_WORD" ]]    && ok "theme_$t: egg word" || bad "theme_$t: egg word"
done

theme_hearth
[[ "$CIRCLE_SGR" == "38;5;214" ]] && ok "hearth: CIRCLE_SGR amber" || bad "hearth: CIRCLE_SGR ('$CIRCLE_SGR')"
[[ "$LABEL_SGR" == "" ]] && ok "hearth: LABEL_SGR plain" || bad "hearth: LABEL_SGR ('$LABEL_SGR')"
theme_default
[[ "$CIRCLE_SGR" == "@tier" ]] && ok "default: CIRCLE_SGR @tier" || bad "default: CIRCLE_SGR ('$CIRCLE_SGR')"

echo
if (( fails )); then echo "unit: $fails FAILED"; exit 1; fi
echo "All unit tests passed."
