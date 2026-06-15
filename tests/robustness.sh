#!/usr/bin/env bash
# Robustness tests: malformed / partial / hostile stdin must never leak
# stderr noise, never render a malformed line, and always exit 0 (a broken
# statusline must not break the Claude Code statusline pipeline).
# Also covers the PLAN_SL_NOW determinism hook used by the parity cross-check.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ESC=$(printf '\033')
strip_ansi() { sed -E "s/${ESC}\[[0-9;]*m//g"; }

fails=0
ok()  { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1" >&2; fails=$((fails+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"

# run NAME JSON -> stdout in $out, stderr in $err, exit code in $rc
run() {
  local json=$1
  out=$(printf '%s' "$json" | HOME="$TMP" bash statusline.sh 2>"$TMP/err")
  rc=$?
  err=$(cat "$TMP/err")
  plain=$(printf '%s' "$out" | strip_ansi)
}

# ── malformed JSON ───────────────────────────────────────────────────────────
run 'not json {'
[[ $rc -eq 0 ]] && ok "malformed: exit 0" || bad "malformed: exit $rc"
[[ -z "$err" ]] && ok "malformed: no stderr leak" || bad "malformed: stderr leaked: $err"
[[ "$plain" == 'Claude │ usage data pending - make a request' ]] \
  && ok "malformed: clean pending line with name" || bad "malformed: got '$plain'"

# ── empty stdin ──────────────────────────────────────────────────────────────
run ''
[[ $rc -eq 0 && -z "$err" ]] && ok "empty stdin: exit 0, quiet stderr" || bad "empty stdin: rc=$rc err=$err"
[[ "$plain" == 'Claude │ usage data pending - make a request' ]] \
  && ok "empty stdin: clean pending line" || bad "empty stdin: got '$plain'"

# ── model object missing entirely (but rate limits present) ─────────────────
run '{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1746234000}}}'
[[ "$plain" == Claude*'5h: 42%'* ]] && ok "no model: falls back to Claude" || bad "no model: got '$plain'"

# ── fractional + string percentages truncate like integers ──────────────────
run '{"model":{"display_name":"M"},"rate_limits":{"five_hour":{"used_percentage":42.7,"resets_at":1746234000}}}'
[[ "$plain" == *'5h: 42%'* ]] && ok "fractional pct: truncates (42.7 -> 42)" || bad "fractional pct: got '$plain'"
run '{"model":{"display_name":"M"},"rate_limits":{"five_hour":{"used_percentage":"42","resets_at":1746234000}}}'
[[ "$plain" == *'5h: 42%'* ]] && ok "string pct: tolerated" || bad "string pct: got '$plain'"

# ── missing resets_at renders without crashing ───────────────────────────────
run '{"model":{"display_name":"M"},"rate_limits":{"five_hour":{"used_percentage":42}}}'
[[ $rc -eq 0 && "$plain" == *'5h: 42%'* ]] && ok "missing resets_at: renders" || bad "missing resets_at: rc=$rc got '$plain'"

# ── config parsing: spaces, quotes, comment lines ────────────────────────────
printf '# pick a theme\ntheme = "glow"\n' > "$TMP/.claude/plan-statusline.conf"
run '{"model":{"display_name":"M"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1746234000}}}'
[[ "$out" == *"${ESC}[1;38;5;199mM"* ]] && ok "conf: spaces/quotes/comments parse (glow name)" \
  || bad "conf parse: got '$out'"
rm -f "$TMP/.claude/plan-statusline.conf"

# ── PLAN_SL_NOW pins the egg flash (determinism hook) ────────────────────────
PEGGED='{"model":{"display_name":"M"},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1746234000}}}'
printf 'theme=scrubs\n' > "$TMP/.claude/plan-statusline.conf"
a=$(printf '%s' "$PEGGED" | PLAN_SL_NOW=1000000 HOME="$TMP" bash statusline.sh | strip_ansi)
b=$(printf '%s' "$PEGGED" | PLAN_SL_NOW=1000001 HOME="$TMP" bash statusline.sh | strip_ansi)
[[ "$a" == *'CODE BLUE'* ]] && ok "PLAN_SL_NOW even: egg msg A" || bad "egg A: got '$a'"
[[ "$b" == *'▁▁▁▁▁▁▁▁▁'* ]] && ok "PLAN_SL_NOW odd: egg msg B"  || bad "egg B: got '$b'"
a2=$(printf '%s' "$PEGGED" | PLAN_SL_NOW=1000000 HOME="$TMP" bash statusline.sh)
a3=$(printf '%s' "$PEGGED" | PLAN_SL_NOW=1000000 HOME="$TMP" bash statusline.sh)
[[ "$a2" == "$a3" ]] && ok "PLAN_SL_NOW: byte-stable across runs" || bad "PLAN_SL_NOW: unstable output"
rm -f "$TMP/.claude/plan-statusline.conf"

# ── PLAN_SL_NOW pins fmt_when's today check ──────────────────────────────────
# week reset 2h after "now" -> same local day -> clock time, not weekday.
now=1746234000
soon=$((now + 7200))
json="{\"model\":{\"display_name\":\"M\"},\"rate_limits\":{\"seven_day\":{\"used_percentage\":50,\"resets_at\":$soon}}}"
w=$(printf '%s' "$json" | PLAN_SL_NOW=$now HOME="$TMP" TZ=UTC bash statusline.sh | strip_ansi)
[[ "$w" == *':'*'m)'* ]] && ok "PLAN_SL_NOW: same-day week reset shows clock time" || bad "same-day week reset: got '$w'"

# ── NO_COLOR: suppress all ANSI, keep glyphs + layout ────────────────────────
NCJSON='{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1746234000},"seven_day":{"used_percentage":78,"resets_at":1746500400}},"context_window":{"used_percentage":15,"context_window_size":1000000}}'
ncout=$(printf '%s' "$NCJSON" | NO_COLOR=1 HOME="$TMP" bash statusline.sh)
if printf '%s' "$ncout" | grep -q "$ESC"; then bad "NO_COLOR: still emitted ESC bytes"; else ok "NO_COLOR: zero ESC bytes"; fi
# layout/glyphs survive: plain text still has the circle, separators, and values
[[ "$ncout" == *"Opus 4.8"*"5h: 42%"*"week: 78%"*"15% of 1M"* ]] && ok "NO_COLOR: layout + values intact" || bad "NO_COLOR layout: got '$ncout'"
[[ "$ncout" == *"◔"* || "$ncout" == *"â"* || "$ncout" == *"of 1M"* ]] && ok "NO_COLOR: context glyph present" || bad "NO_COLOR glyph"
# pegged egg still renders its word, just uncolored
printf 'theme=scrubs
' > "$TMP/.claude/plan-statusline.conf"
ncegg=$(printf '%s' "$PEGGED" | NO_COLOR=1 PLAN_SL_NOW=1000000 HOME="$TMP" bash statusline.sh)
if printf '%s' "$ncegg" | grep -q "$ESC"; then bad "NO_COLOR egg: ESC bytes leaked"; else ok "NO_COLOR egg: zero ESC bytes"; fi
[[ "$ncegg" == *"CODE BLUE"* && "$ncegg" == *"defib"* ]] && ok "NO_COLOR egg: word intact" || bad "NO_COLOR egg word: got '$ncegg'"
rm -f "$TMP/.claude/plan-statusline.conf"
# missing-jq path also respects NO_COLOR (no red wrapper)
jqdir=$(mktemp -d); for t in bash cat printf sed tr date mktemp grep; do tp=$(command -v "$t"); [[ -n "$tp" ]] && ln -s "$tp" "$jqdir/$t"; done
nojq=$(printf '%s' "$NCJSON" | PATH="$jqdir" NO_COLOR=1 HOME="$TMP" bash statusline.sh)
if printf '%s' "$nojq" | grep -q "$ESC"; then bad "NO_COLOR missing-jq: ESC leaked"; else ok "NO_COLOR missing-jq: plain"; fi
rm -rf "$jqdir"

echo
if (( fails )); then echo "robustness: $fails FAILED"; exit 1; fi
echo "All robustness tests passed."
