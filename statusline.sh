#!/usr/bin/env bash
# Claude Code statusline that shows plan rate-limit usage (5-hour session + 7-day weekly).
# Reads Claude Code's statusline JSON from stdin — no network, no auth, just jq.
# Requires Claude Code v2.1.80+ (when rate_limits was added to statusline stdin).
#
# Themes: select via ~/.claude/plan-statusline.conf, e.g.:
#   theme=default   # today's look (the safe one)
#   theme=hearth    # warm amber, pulsing sparkle, model-name shimmer
#   theme=glow      # bold bright neon-style, animated sparkle
# Missing or invalid theme → default.

set -uo pipefail

# ============================================================================
# Shared helpers (used by every theme)
# ============================================================================

# Format an epoch with a strftime string. BSD date (macOS) uses `-r`; GNU date (Linux/WSL) uses `-d @`.
date_fmt() {
  local epoch=$1 fmt=$2
  date -r "$epoch" "$fmt" 2>/dev/null || date -d "@$epoch" "$fmt" 2>/dev/null
}

fmt_time() {
  local epoch=$1
  [[ -z "$epoch" ]] && return
  date_fmt "$epoch" "+%-I:%M%p" | tr '[:upper:]' '[:lower:]'
}

fmt_size() {
  local n=$1
  [[ -z "$n" ]] && return
  if   ((n >= 1000000)); then printf '%dM' $((n / 1000000))
  elif ((n >= 1000));    then printf '%dk' $((n / 1000))
  else                        printf '%d' "$n"
  fi
}

fmt_when() {
  local epoch=$1
  [[ -z "$epoch" ]] && return
  if [[ "$(date_fmt "$epoch" "+%Y-%m-%d")" == "$(date "+%Y-%m-%d")" ]]; then
    fmt_time "$epoch"
  else
    date_fmt "$epoch" "+%a" | tr '[:upper:]' '[:lower:]'
  fi
}

# Five-step fill circle, used by every theme.
ctx_circle() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 88)); then printf '●'
  elif ((pct >= 63)); then printf '◕'
  elif ((pct >= 38)); then printf '◑'
  elif ((pct >= 13)); then printf '◔'
  else                     printf '○'
  fi
}

# True when either rate limit is pegged at 100% — drives each theme's
# 100% easter egg state (flatline, burnout, game over, skull).
limit_pegged() {
  { [[ -n "$five_pct" ]] && (( ${five_pct%.*} >= 100 )); } ||
  { [[ -n "$week_pct" ]] && (( ${week_pct%.*} >= 100 )); }
}

# Milliseconds since epoch from the best available source. The statusline is a
# fresh process per repaint, so the sweep position must come from wall-clock time.
# Prefer sources that spawn no extra process; degrade to whole seconds last.
now_ms() {
  # bash 5+: EPOCHREALTIME = "seconds.microseconds" — no subprocess.
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local er=${EPOCHREALTIME//,/.}        # normalize locale radix (de_DE etc.)
    local s=${er%.*} us=${er#*.}
    us=${us}000000; us=${us:0:6}
    printf '%d' $(( 10#$s * 1000 + 10#$us / 1000 ))
    return
  fi
  # GNU date and modern macOS date emit nanoseconds; older BSD date prints a
  # literal 'N' -> the digit regex gates it either way.
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
  # '@tier' sentinel: circle/label color tracks the value's tier color (all-one-span).
  CIRCLE_SGR='@tier'; LABEL_SGR='@tier'
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
  CIRCLE_SGR='38;5;214'; LABEL_SGR=''
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
  CIRCLE_SGR='@tier'; LABEL_SGR='@tier'
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
  CIRCLE_SGR='@tier'; LABEL_SGR='@tier'
  EGG_GLYPH=''; EGG_GLYPH_COLOR=''
  EGG_MSG_A='CODE BLUE';      EGG_COLOR_A='1;38;5;196'
  EGG_MSG_B='▁▁▁▁▁▁▁▁▁';      EGG_COLOR_B='1;38;5;196'   # flashes (text <-> flat trace)
  EGG_RESET_WORD='defib'
}

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

# Resolve a span-color spec against the value's tier color: '@tier' -> tier,
# anything else (including '' = default fg) is used literally.
span_sgr() { if [[ "$1" == '@tier' ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# A rate segment (5h / week). Circle, label, and value are painted as separate
# spans so each can take its own color (hearth: amber circle, plain label,
# tier value; others: all tier). Falls through to the easter egg at 100%.
seg_rate() {
  local label=$1 pctraw=$2 reset_str=$3
  local pct=${pctraw%.*}
  if (( pct >= 100 )); then egg "$label" "$reset_str"; return; fi
  local tier; tier=$(tier_color "$pct")
  if (( SEG_CIRCLE )); then
    paint "$(span_sgr "$CIRCLE_SGR" "$tier")" "$(ctx_circle "$pct")"; printf ' '
  fi
  paint "$(span_sgr "$LABEL_SGR" "$tier")" "${label}${LABEL_SEP}"
  printf ' '
  paint "$tier" "${pct}%"
  printf ' '
  paint "$(meta_sgr '')" "(→${reset_str})"
}

# The context segment: always circled, no label / reset / egg. Circle uses
# CIRCLE_SGR (hearth: amber; others: tier); value uses tier; size uses META
# (or tier when META is empty, matching default's original look).
seg_ctx() {
  local pctraw=$1 size=$2
  local pct=${pctraw%.*}
  local tier; tier=$(tier_color "$pct")
  paint "$(span_sgr "$CIRCLE_SGR" "$tier")" "$(ctx_circle "$pct")"; printf ' '
  paint "$tier" "${pct}%"
  [[ -n "$size" ]] && paint "$(meta_sgr "$tier")" "$size"
}

# 100% easter egg for a rate segment. Flashes A<->B per second when they differ.
# The label is colored like the message EXCEPT when LABEL_SGR is empty (hearth),
# where it stays default-fg. The reset clause uses META, or plain when META is
# empty (default), matching the originals.
egg() {
  local label=$1 reset_str=$2 msg col lblcol
  if (( $(date +%s) % 2 )) && [[ "$EGG_MSG_A" != "$EGG_MSG_B" ]]; then
    msg=$EGG_MSG_B; col=$EGG_COLOR_B
  else
    msg=$EGG_MSG_A; col=$EGG_COLOR_A
  fi
  [[ -n "$EGG_GLYPH" ]] && printf '\033[%sm%s\033[0m ' "$EGG_GLYPH_COLOR" "$EGG_GLYPH"
  if [[ -n "$LABEL_SGR" ]]; then lblcol=$col; else lblcol=''; fi
  paint "$lblcol" "${label}${LABEL_SEP}"
  printf ' '
  paint "$col" "$msg"
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

# ============================================================================
# main — only runs when executed, not when sourced
# ============================================================================

main() {
  input=$(cat)

  # --- Config: read theme name from ~/.claude/plan-statusline.conf if present ---
  theme=default
  config_file="${HOME}/.claude/plan-statusline.conf"
  if [[ -f "$config_file" ]]; then
    while IFS='=' read -r key value; do
      key=${key// /}
      value=${value// /}
      value=${value%\"}; value=${value#\"}
      case "$key" in
        theme) [[ -n "$value" ]] && theme="$value" ;;
      esac
    done < "$config_file"
  fi

  # --- Parse stdin JSON (one jq call into 7 vars) ---
  # Join with the ASCII unit separator (\x1f), NOT @tsv: tab counts as IFS
  # *whitespace*, so bash `read` collapses consecutive tabs and empty fields
  # shift everything left (a missing context % once rendered the 1M window
  # size as "1000000%"). Non-whitespace delimiters preserve empty fields.
  IFS=$'\x1f' read -r model five_pct five_reset week_pct week_reset ctx_pct ctx_size < <(
    printf '%s' "$input" | jq -r '[
      .model.display_name // .model.id // "Claude",
      .rate_limits.five_hour.used_percentage // "",
      .rate_limits.five_hour.resets_at // "",
      .rate_limits.seven_day.used_percentage // "",
      .rate_limits.seven_day.resets_at // "",
      .context_window.used_percentage // "",
      .context_window.context_window_size // ""
    ] | map(tostring) | join("\u001f")'
  )

  # --- Dispatch: load theme data, render once ---
  case "$theme" in
    hearth) theme_hearth ;;
    glow)   theme_glow ;;
    scrubs) theme_scrubs ;;
    default|*) theme_default ;;
  esac
  render_line
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
