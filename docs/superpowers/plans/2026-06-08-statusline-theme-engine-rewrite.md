# Statusline Theme Engine Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace four near-identical `render_<theme>` functions in `statusline.sh` with one data-driven renderer, and add a smooth gradient sweep on the model name across all themes.

**Architecture:** Each theme becomes a loader function that sets a fixed set of globals (palette, flags, easter-egg strings, sweep ramp). One shared `render_line` consumes them. New shared primitives `now_ms()` (best-available millisecond clock) and `sweep()` (moving gradient band) provide the animation. The stdin-read + dispatch is wrapped in `main()` guarded by `BASH_SOURCE` so functions are unit-testable.

**Tech Stack:** Bash 3.2 (macOS default — indexed arrays only, no `declare -A`), `jq`, BSD/GNU `date`, optional `perl`/`python3` for the millisecond clock.

**Reference spec:** `docs/superpowers/specs/2026-06-08-statusline-theme-engine-rewrite-design.md`

---

## File Structure

- **Modify** `statusline.sh` — the whole rewrite. New layout top→bottom: shebang/comment, `set -uo pipefail`, shared helpers (`date_fmt`, `fmt_time`, `fmt_size`, `fmt_when`, `ctx_circle`, `limit_pegged`, `now_ms`, `sweep`, `paint`, `paint_sep`, `tier_color`, `meta_sgr`), theme loaders (`theme_default/hearth/glow/scrubs`), segment helpers (`seg_rate`, `seg_ctx`, `egg`), `render_line`, `main`, `BASH_SOURCE` guard.
- **Modify** `tests/dispatch.sh` — add faithfulness substring assertions + a pegged-state (100%) case.
- **Create** `tests/unit.sh` — sourced unit tests for `now_ms`, `sweep`, and the theme loaders.
- **Modify** `tests/xterm-hex.sh` — update per-theme color index lists to the new palette.
- **Modify** `README.md` — update Themes table/descriptions for the sweep; note default now animates.

**Always-green invariant:** Tasks 1–5 only ADD code; `main` keeps calling the OLD `case → render_<theme>` dispatch, so `tests/dispatch.sh` passes throughout. Task 6 swaps the dispatch and deletes the old code in one commit.

---

### Task 1: Make the script sourceable (`main()` + guard)

Wrap the stdin read, config read, and jq parse (currently top-level, lines ~14–45) plus the dispatch `case` into a `main()` function, and only run it when executed (not sourced). This stops `input=$(cat)` from blocking when a test sources the file, and exposes every function for unit testing. **Behavior is unchanged** — old `render_<theme>` functions stay and `main` still calls the old dispatch `case`.

**Files:**
- Modify: `statusline.sh` (move lines ~14–45 and the dispatch `case` at the bottom into `main`)

- [ ] **Step 1: Add the failing test**

Create `tests/unit.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/unit.sh`
Expected: hangs (Ctrl-C) or fails — the current script runs `input=$(cat)` and the dispatch on source. (If it hangs, that IS the failure this task fixes.)

- [ ] **Step 3: Wrap execution in `main()` + guard**

In `statusline.sh`, move the stdin read, the config-file block, and the jq parse block into a function `main()`. Move the bottom dispatch `case` into `main()` too. Use no `local` for `theme`, `model`, `five_pct`, `five_reset`, `week_pct`, `week_reset`, `ctx_pct`, `ctx_size` so they stay global (the render functions read them as globals). Result (showing only the new wrapper shape — keep the existing body content verbatim inside):

```bash
main() {
  input=$(cat)

  # --- Config: read theme name (existing block, verbatim) ---
  theme=default
  config_file="${HOME}/.claude/plan-statusline.conf"
  if [[ -f "$config_file" ]]; then
    while IFS='=' read -r key value; do
      key=${key// /}; value=${value// /}
      value=${value%\"}; value=${value#\"}
      case "$key" in theme) [[ -n "$value" ]] && theme="$value" ;; esac
    done < "$config_file"
  fi

  # --- Parse stdin JSON (existing jq block, verbatim) ---
  IFS=$'\x1f' read -r model five_pct five_reset week_pct week_reset ctx_pct ctx_size < <(
    printf '%s' "$input" | jq -r '[
      .model.display_name // .model.id // "Claude",
      .rate_limits.five_hour.used_percentage // "",
      .rate_limits.five_hour.resets_at // "",
      .rate_limits.seven_day.used_percentage // "",
      .rate_limits.seven_day.resets_at // "",
      .context_window.used_percentage // "",
      .context_window.context_window_size // ""
    ] | map(tostring) | join("")'
  )

  # --- Dispatch (existing case, verbatim for now) ---
  case "$theme" in
    hearth)         render_hearth ;;
    glow)           render_glow ;;
    scrubs)         render_scrubs ;;
    default|*)      render_default ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
```

Keep all `set -uo pipefail`, comments, and the existing helper/render functions where they are (above `main`). The `BASH_SOURCE` guard goes at the very bottom.

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/unit.sh && bash tests/dispatch.sh`
Expected: `All unit tests passed.` and `All dispatch tests passed.` (dispatch still green — behavior unchanged).

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/unit.sh
git commit -m "Wrap execution in main() + BASH_SOURCE guard for testability"
```

---

### Task 2: `now_ms()` — best-available millisecond clock

**Files:**
- Modify: `statusline.sh` (add `now_ms` next to the other shared helpers, after `limit_pegged`)
- Modify: `tests/unit.sh`

- [ ] **Step 1: Add the failing test**

Append to `tests/unit.sh`, just before the final summary block:

```bash
# now_ms returns integer milliseconds, sane magnitude (> year 2001 in ms).
ms=$(now_ms)
[[ "$ms" =~ ^[0-9]+$ ]] && ok "now_ms: integer ($ms)" || bad "now_ms: integer (got '$ms')"
(( ms > 1000000000000 )) && ok "now_ms: magnitude" || bad "now_ms: magnitude ($ms)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/unit.sh`
Expected: FAIL — `now_ms: command not found` / function undefined.

- [ ] **Step 3: Implement `now_ms()`**

Add to `statusline.sh` after `limit_pegged()`:

```bash
# Milliseconds since epoch from the best available source. The statusline is a
# fresh process per repaint, so the sweep position must come from wall-clock time.
# Prefer sources that spawn no extra process; degrade to whole seconds last.
now_ms() {
  # bash 5+: EPOCHREALTIME = "seconds.microseconds" — no subprocess.
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local s=${EPOCHREALTIME%.*} us=${EPOCHREALTIME#*.}
    us=${us}000000; us=${us:0:6}
    printf '%d' $(( 10#$s * 1000 + 10#$us / 1000 ))
    return
  fi
  # GNU date: nanoseconds. BSD date prints a literal 'N' -> regex rejects it.
  local ns
  ns=$(date +%s%N 2>/dev/null)
  if [[ "$ns" =~ ^[0-9]+$ ]]; then
    printf '%d' $(( ns / 1000000 ))
    return
  fi
  # perl (preinstalled on macOS).
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' && return
  fi
  # python3.
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))' && return
  fi
  # Last resort: whole seconds.
  printf '%d' $(( $(date +%s) * 1000 ))
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/unit.sh`
Expected: `now_ms: integer` and `now_ms: magnitude` PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/unit.sh
git commit -m "Add now_ms(): best-available millisecond clock with seconds fallback"
```

---

### Task 3: `sweep()` — gradient band over text

Depends on `SWEEP_RAMP` (set by a theme loader), `limit_pegged`, `now_ms`.

**Files:**
- Modify: `statusline.sh` (add `sweep` after `now_ms`)
- Modify: `tests/unit.sh`

- [ ] **Step 1: Add the failing test**

Append to `tests/unit.sh`, before the summary block:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/unit.sh`
Expected: FAIL — `sweep` undefined.

- [ ] **Step 3: Implement `sweep()`**

Add to `statusline.sh` after `now_ms()`:

```bash
# Gradient band swept across TEXT, colored from the active theme's SWEEP_RAMP
# (base mid peak). Each character emits an EXPLICIT SGR so the peak color cannot
# bleed into following base characters (empty base -> emit reset). ANSI-stripped
# output equals TEXT exactly.
sweep() {
  local text=$1
  local n=${#text}
  (( n == 0 )) && return
  # Pegged: the name "dies" — frozen, dim, no motion.
  if limit_pegged; then
    printf '\033[2m%s\033[0m' "$text"
    return
  fi
  local base=${SWEEP_RAMP[0]} mid=${SWEEP_RAMP[1]} peak=${SWEEP_RAMP[2]}
  local period=2200 pad=4
  local ms; ms=$(now_ms)
  local center=$(( (ms % period) * (n + pad) / period - pad / 2 ))
  local i d sgr char
  for (( i = 0; i < n; i++ )); do
    d=$(( i - center )); (( d < 0 )) && d=$(( -d ))
    if   (( d == 0 )); then sgr=$peak
    elif (( d == 1 )); then sgr=$mid
    else                    sgr=$base
    fi
    char=${text:i:1}
    if [[ -n "$sgr" ]]; then
      printf '\033[%sm%s' "$sgr" "$char"
    else
      printf '\033[0m%s' "$char"
    fi
  done
  printf '\033[0m'
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/unit.sh`
Expected: all `sweep:` assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/unit.sh
git commit -m "Add sweep(): moving gradient band over text, ANSI-strip stable"
```

---

### Task 4: Theme loaders

Add `theme_default/hearth/glow/scrubs` that set the schema globals. These are pure data — no rendering. (Old `render_*` still active; this only adds functions.)

**Files:**
- Modify: `statusline.sh` (add the four loaders after `sweep`)
- Modify: `tests/unit.sh`

- [ ] **Step 1: Add the failing test**

Append to `tests/unit.sh`, before the summary:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/unit.sh`
Expected: FAIL — `theme_default` undefined.

- [ ] **Step 3: Implement the loaders**

Add to `statusline.sh` after `sweep()`. ANSI values are SGR parameters (the part between `\033[` and `m`); empty string means "terminal default fg / no code".

```bash
# ============================================================================
# Theme loaders — each sets the globals render_line consumes. Pure data.
# Tier thresholds are shared: urgent >=90, hot >=70, warn >=50, else calm.
# Empty TIER_* = terminal default fg (used by hearth's silent calm/warn).
# ============================================================================

theme_default() {            # basic ANSI, faithful to the original look
  TIER_CALM=32; TIER_WARN=33; TIER_HOT='38;5;208'; TIER_URGENT=31
  SWEEP_RAMP=( '' '38;5;252' '1;38;5;255' )   # plain -> grey -> bold white band
  SEP=' │ '; SEP_COLOR=''
  META=''                                      # reset/size inherit tier color
  SEG_CIRCLE=0; LABEL_SEP=':'
  EGG_GLYPH=''; EGG_GLYPH_COLOR=''
  EGG_MSG_A='100% 💀'; EGG_COLOR_A=31
  EGG_MSG_B='100% 💀'; EGG_COLOR_B=31          # equal -> no flash
  EGG_RESET_WORD='respawn'
}

theme_hearth() {             # warm amber, restrained (silent calm/warn)
  TIER_CALM=''; TIER_WARN=''; TIER_HOT='38;5;208'; TIER_URGENT='1;38;5;196'
  SWEEP_RAMP=( '38;5;214' '38;5;221' '1;38;5;230' )   # amber -> gold -> pale gold
  SEP=' · '; SEP_COLOR=2
  META='2;3'                                   # dim italic
  SEG_CIRCLE=1; LABEL_SEP=''
  EGG_GLYPH='○'; EGG_GLYPH_COLOR=2
  EGG_MSG_A='burnt out'; EGG_COLOR_A='1;38;5;196'
  EGG_MSG_B='burnt out'; EGG_COLOR_B='1;38;5;196'
  EGG_RESET_WORD='rekindles'
}

theme_glow() {               # pink neon arcade
  TIER_CALM='1;38;5;41'; TIER_WARN='1;38;5;205'; TIER_HOT='1;38;5;199'; TIER_URGENT='1;38;5;197'
  SWEEP_RAMP=( '1;38;5;205' '1;38;5;199' '1;38;5;231' )   # pink -> magenta -> white-hot
  SEP=' · '; SEP_COLOR=2
  META='3;38;5;175'                            # italic rose
  SEG_CIRCLE=1; LABEL_SEP=''
  EGG_GLYPH=''; EGG_GLYPH_COLOR=''
  EGG_MSG_A='GAME OVER';   EGG_COLOR_A='1;38;5;197'
  EGG_MSG_B='INSERT COIN'; EGG_COLOR_B='1;38;5;199'   # flashes
  EGG_RESET_WORD='1UP'
}

theme_scrubs() {             # clinical teal vitals monitor
  TIER_CALM='38;5;30'; TIER_WARN='1;38;5;37'; TIER_HOT='38;5;214'; TIER_URGENT='1;38;5;196'
  SWEEP_RAMP=( '38;5;30' '38;5;37' '1;38;5;159' )   # teal -> bright teal -> pale cyan
  SEP=' · '; SEP_COLOR=2
  META='3;38;5;152'                            # italic light teal
  SEG_CIRCLE=1; LABEL_SEP=''
  EGG_GLYPH=''; EGG_GLYPH_COLOR=''
  EGG_MSG_A='CODE BLUE';      EGG_COLOR_A='1;38;5;196'
  EGG_MSG_B='▁▁▁▁▁▁▁▁▁';      EGG_COLOR_B='1;38;5;196'   # flashes (text <-> flat trace)
  EGG_RESET_WORD='defib'
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/unit.sh`
Expected: all `theme_*` assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/unit.sh
git commit -m "Add data-driven theme loaders (default/hearth/glow/scrubs)"
```

---

### Task 5: `render_line()` + segment helpers

Add `paint`, `paint_sep`, `tier_color`, `meta_sgr`, `seg_rate`, `seg_ctx`, `egg`, and `render_line`. Test faithfulness via subprocess in `tests/dispatch.sh` (TZ-independent substrings). Old dispatch still active — `render_line` is not yet wired in.

**Files:**
- Modify: `statusline.sh` (add helpers + `render_line` after the theme loaders)
- Modify: `tests/dispatch.sh`

- [ ] **Step 1: Add the failing test**

In `tests/dispatch.sh`, add a pegged sample near the existing `SAMPLE`/`EMPTY`:

```bash
PEGGED='{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1746234000},"seven_day":{"used_percentage":78,"resets_at":1746500400}},"context_window":{"used_percentage":15,"context_window_size":1000000}}'
```

Then, after the existing assertion blocks (before the final `echo`), add a temporary direct-render check that exercises `render_line` ahead of the dispatch swap. Append:

```bash
# --- render_line faithfulness (TZ-independent substrings) ---
# Drive render_line directly by sourcing, loading a theme, setting parsed vars.
render_check() {
  local theme=$1 expect=$2
  local plain
  plain=$(
    five_pct=42 five_reset=1746234000 \
    week_pct=78 week_reset=1746500400 \
    ctx_pct=15 ctx_size=1000000 model='Opus 4.8' \
    bash -c "source ./statusline.sh; theme_$theme; render_line" | strip_ansi
  )
  if [[ "$plain" != *"$expect"* ]]; then
    printf 'FAIL render theme=%-8s expected %q\n  got: %s\n' "$theme" "$expect" "$plain" >&2
    return 1
  fi
  printf 'PASS render theme=%-8s (matched %q)\n' "$theme" "$expect"
}

render_check default "5h: 42%"
render_check default "◔ 15% of 1M"
for t in hearth glow scrubs; do
  render_check "$t" "◑ 5h 42%"
  render_check "$t" "◕ week 78%"
done
```

Also add pegged easter-egg checks (stable reset words, no flash dependence) using the existing `assert_renders` (which goes through the dispatch — these will pass only after Task 6 wires `render_line` in, so guard them under Task 6). For THIS task, add only the `render_check`-based pegged egg checks:

```bash
egg_check() {
  local theme=$1 expect=$2 plain
  plain=$(
    five_pct=100 five_reset=1746234000 \
    week_pct=78 week_reset=1746500400 \
    ctx_pct=15 ctx_size=1000000 model='Opus 4.8' \
    bash -c "source ./statusline.sh; theme_$theme; render_line" | strip_ansi
  )
  [[ "$plain" == *"$expect"* ]] && printf 'PASS egg theme=%-8s (%q)\n' "$theme" "$expect" \
    || { printf 'FAIL egg theme=%-8s expected %q got: %s\n' "$theme" "$expect" "$plain" >&2; return 1; }
}
egg_check default respawn
egg_check hearth rekindles
egg_check glow 1UP
egg_check scrubs defib
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/dispatch.sh`
Expected: FAIL — `render_line` undefined / empty output.

- [ ] **Step 3: Implement the renderer + helpers**

Add to `statusline.sh` after the theme loaders:

```bash
# ============================================================================
# Shared renderer
# ============================================================================

# Wrap TEXT in an SGR if non-empty (self-terminating); else print plain.
paint() {
  local sgr=$1 text=$2
  if [[ -n "$sgr" ]]; then printf '\033[%sm%s\033[0m' "$sgr" "$text"
  else printf '%s' "$text"; fi
}

paint_sep() { paint "$SEP_COLOR" "$SEP"; }

# SGR for a percentage by shared tier thresholds (may be empty = default fg).
tier_color() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   (( pct >= 90 )); then printf '%s' "$TIER_URGENT"
  elif (( pct >= 70 )); then printf '%s' "$TIER_HOT"
  elif (( pct >= 50 )); then printf '%s' "$TIER_WARN"
  else                       printf '%s' "$TIER_CALM"
  fi
}

# Meta SGR: explicit META if set, else inherit the segment's tier SGR
# (so default's reset times / size label match the value color, as before).
meta_sgr() { if [[ -n "$META" ]]; then printf '%s' "$META"; else printf '%s' "$1"; fi; }

# A rate segment (5h / week): "[circle ]label<sep> pct% (->reset)" or the egg.
seg_rate() {
  local label=$1 pctraw=$2 reset_str=$3
  local pct=${pctraw%.*}
  if (( pct >= 100 )); then egg "$label" "$reset_str"; return; fi
  local tier; tier=$(tier_color "$pct")
  local circle=''
  (( SEG_CIRCLE )) && circle="$(ctx_circle "$pct") "
  paint "$tier" "${circle}${label}${LABEL_SEP} ${pct}%"
  printf ' '
  paint "$(meta_sgr "$tier")" "(→${reset_str})"
}

# The context segment: always circled, no label / reset / egg.
seg_ctx() {
  local pctraw=$1 size=$2
  local pct=${pctraw%.*}
  local tier; tier=$(tier_color "$pct")
  paint "$tier" "$(ctx_circle "$pct") ${pct}%"
  [[ -n "$size" ]] && paint "$(meta_sgr "$tier")" "$size"
}

# 100% easter egg for a rate segment. Flashes A<->B per second when they differ.
egg() {
  local label=$1 reset_str=$2 msg col
  if (( $(date +%s) % 2 )) && [[ "$EGG_MSG_A" != "$EGG_MSG_B" ]]; then
    msg=$EGG_MSG_B; col=$EGG_COLOR_B
  else
    msg=$EGG_MSG_A; col=$EGG_COLOR_A
  fi
  [[ -n "$EGG_GLYPH" ]] && printf '\033[%sm%s\033[0m ' "$EGG_GLYPH_COLOR" "$EGG_GLYPH"
  paint "$col" "${label}${LABEL_SEP} ${msg}"
  printf ' '
  if [[ -n "$META" ]]; then
    paint "$META" "(${EGG_RESET_WORD} →${reset_str})"
  else
    printf '(%s →%s)' "$EGG_RESET_WORD" "$reset_str"
  fi
}

# The one renderer: swept model name, then any present segments joined by SEP.
render_line() {
  if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
    sweep "$model"; paint_sep
    paint "$META" 'usage data pending - make a request'
    return
  fi
  sweep "$model"
  [[ -n "$five_pct" ]] && { paint_sep; seg_rate '5h' "$five_pct" "$(fmt_time "$five_reset")"; }
  [[ -n "$week_pct" ]] && { paint_sep; seg_rate 'week' "$week_pct" "$(fmt_when "$week_reset")"; }
  if [[ -n "$ctx_pct" ]]; then
    local size=''; [[ -n "$ctx_size" ]] && size=" of $(fmt_size "$ctx_size")"
    paint_sep; seg_ctx "$ctx_pct" "$size"
  fi
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/dispatch.sh`
Expected: all `render` and `egg` checks PASS; the original assertions still PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/dispatch.sh
git commit -m "Add data-driven render_line() + segment/egg helpers"
```

---

### Task 6: Swap dispatch to `render_line` and delete the old code

Wire the new engine into `main()` and remove every now-dead symbol in one commit so the file is clean and the always-green invariant is preserved.

**Files:**
- Modify: `statusline.sh` (dispatch swap + deletions)
- Modify: `tests/dispatch.sh` (move the egg checks to the real dispatch path)

- [ ] **Step 1: Swap the dispatch in `main()`**

Replace the dispatch `case` inside `main()` with: load the theme, then render once.

```bash
  # --- Dispatch: load theme data, render once ---
  case "$theme" in
    hearth) theme_hearth ;;
    glow)   theme_glow ;;
    scrubs) theme_scrubs ;;
    default|*) theme_default ;;
  esac
  render_line
```

- [ ] **Step 2: Delete the old code**

Remove these now-dead definitions from `statusline.sh` entirely:
- `reset_color`
- `SPARKLES` array + `sparkle_now`
- `default_color`, `render_default`
- `H_*` color vars, `hearth_tier_fg`, `hearth_shimmer`, `HEARTH_SMOKE`, `hearth_spark`, `hearth_burnout`, `render_hearth`
- `G_*` color vars, `glow_tier_fg`, `glow_gameover`, `render_glow`
- `S_*` color vars, `SCRUBS_BEAT`, `scrubs_beat`, `scrubs_flatline`, `scrubs_tier_fg`, `render_scrubs`

Keep: `date_fmt`, `fmt_time`, `fmt_size`, `fmt_when`, `ctx_circle`, `limit_pegged`, `now_ms`, `sweep`, all theme loaders, `paint`, `paint_sep`, `tier_color`, `meta_sgr`, `seg_rate`, `seg_ctx`, `egg`, `render_line`, `main`, the guard.

- [ ] **Step 3: Promote egg checks to the real dispatch path**

In `tests/dispatch.sh`, add (alongside the existing `assert_renders` block) checks that go through the actual installed dispatch with a config file (proves the swap works end-to-end):

```bash
# Pegged state flows through dispatch -> render_line -> egg (stable reset words).
assert_renders default "$PEGGED" "respawn"
assert_renders hearth  "$PEGGED" "rekindles"
assert_renders glow    "$PEGGED" "1UP"
assert_renders scrubs  "$PEGGED" "defib"
assert_renders default "$PEGGED" "100% 💀"
```

- [ ] **Step 4: Run the full suite**

Run: `bash tests/unit.sh && bash tests/dispatch.sh`
Expected: both print their "All ... passed." lines. Manually eyeball each theme live:

```bash
for t in default hearth glow scrubs; do
  printf 'theme=%s\n' "$t" > /tmp/sl.conf
  echo '{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1746234000},"seven_day":{"used_percentage":78,"resets_at":1746500400}},"context_window":{"used_percentage":15,"context_window_size":1000000}}' \
    | HOME=/tmp bash statusline.sh; echo
done
```
Expected: four themed lines, model name visibly color-swept, segments faithful to the old looks. (Re-run a few times — the sweep band position shifts with time.)

- [ ] **Step 5: Commit**

```bash
git add statusline.sh tests/dispatch.sh
git commit -m "Swap dispatch to data-driven render_line; delete old per-theme code"
```

---

### Task 7: Update `tests/xterm-hex.sh` palette reference

The dev helper lists each theme's color cube indices. Update to the new palette/ramp so `./tests/xterm-hex.sh` (no args) prints accurate hexes.

**Files:**
- Modify: `tests/xterm-hex.sh` (the no-arg section, lines ~37–45)

- [ ] **Step 1: Replace the no-arg listing**

Replace the `glow:`/`hearth:` blocks at the bottom with all four themes' indices (tiers + ramps), 256-cube indices only (the helper rejects 0–15 and 232–255 with a message, which is fine to skip — list cube indices):

```bash
printf 'default (tiers 208; ramp 252,255):\n'
for n in 208 252 255; do printf '  %3d → %s\n' "$n" "$(cube_hex "$n")"; done

printf '\nhearth (tiers 208,196; ramp 214,221,230):\n'
for n in 208 196 214 221 230; do printf '  %3d → %s\n' "$n" "$(cube_hex "$n")"; done

printf '\nglow (tiers 41,205,199,197; ramp 205,199,231; meta 175):\n'
for n in 41 205 199 197 231 175; do printf '  %3d → %s\n' "$n" "$(cube_hex "$n")"; done

printf '\nscrubs (tiers 30,37,214,196; ramp 30,37,159; meta 152):\n'
for n in 30 37 214 196 159 152; do printf '  %3d → %s\n' "$n" "$(cube_hex "$n")"; done
```

- [ ] **Step 2: Run it to verify**

Run: `./tests/xterm-hex.sh`
Expected: four labeled blocks, each `index → #rrggbb`, no errors.

- [ ] **Step 3: Commit**

```bash
git add tests/xterm-hex.sh
git commit -m "Update xterm-hex color reference to new theme palette"
```

---

### Task 8: Update `README.md`

**Files:**
- Modify: `README.md` (Themes table + descriptions, lines ~26–33; requirements note)

- [ ] **Step 1: Rewrite the Themes table rows**

Replace the four table rows so each describes the gradient-swept model name (drop sparkle/heartbeat language):

```markdown
| `default`| Basic ANSI colors, pipe separators, single circle on context. The model name carries a restrained white highlight that sweeps across it. |
| `hearth` | Warm amber, restrained. The model name gradient-sweeps amber→gold; tier color stays silent until 70% (orange) / 90% (red). Dim italic reset times. |
| `glow`   | Pink neon arcade. Model name sweeps pink→magenta→white-hot; mint→pink→magenta→red tier ramp; italic rose halo on reset times. |
| `scrubs` | Clinical teal vitals monitor. Model name sweeps teal→bright-teal→pale-cyan; teal→bright→amber→red tier ramp like a patient monitor; soft light-teal halo on reset times. |
```

- [ ] **Step 2: Add a note that the sweep is animated**

Under the Themes section (after the table), add:

```markdown
The model name is animated: a bright band sweeps across it continuously, in each theme's palette. The sweep is smoothest when a millisecond clock is available (`bash` 5+, GNU `date`, `perl`, or `python3` — `perl` ships with macOS); with none of those it falls back to a per-second step. At 100% usage the sweep freezes and the name dims.
```

- [ ] **Step 3: Verify the doc reads correctly**

Run: `sed -n '16,40p' README.md`
Expected: updated table + note, no leftover sparkle/heartbeat descriptions.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Document gradient-sweep model name across themes"
```

---

## Self-Review

**Spec coverage:**
- Data-driven schema + one renderer → Tasks 4, 5, 6. ✓
- Exact per-theme values → Task 4 (matches spec tables; LABEL_SEP corrected to `""` for non-default so "5h 42%" has one space). ✓
- `now_ms` probe order → Task 2. ✓
- `sweep` with bleed-fix (explicit code per char) → Task 3. ✓
- 4 behavior deltas (sweep all themes, glyphs removed, pegged freeze-dim, empty-state unified) → Tasks 3 (freeze), 5 (render_line empty-state + no glyphs), 6 (dispatch). ✓
- Tests: dispatch faithfulness + sweep invariant + xterm-hex → Tasks 5, 3, 7. ✓
- README → Task 8. ✓
- Sourceability (needed to unit-test) → Task 1 (not in spec explicitly, added as enabling step). ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every test step shows the command + expected result. ✓

**Type/name consistency:** Globals (`SWEEP_RAMP`, `TIER_*`, `SEP`, `SEP_COLOR`, `META`, `SEG_CIRCLE`, `LABEL_SEP`, `EGG_*`) are set identically in Task 4 loaders and read identically in Task 5 helpers. `EGG_GLYPH_COLOR` is defined in every loader (Task 4) and read in `egg` (Task 5). `paint`/`paint_sep`/`tier_color`/`meta_sgr`/`seg_rate`/`seg_ctx`/`egg`/`render_line`/`sweep`/`now_ms` names are consistent across tasks. ✓

**Note for executor:** macOS ships **bash 3.2** — do not introduce `declare -A`, `${var^^}`, or `$EPOCHREALTIME`-only assumptions. All arrays are indexed. The `BASH_SOURCE` guard and C-style `for` loops are 3.2-safe.
