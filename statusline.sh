#!/usr/bin/env bash
# Claude Code statusline that shows plan rate-limit usage (5-hour session + 7-day weekly).
# Reads Claude Code's statusline JSON from stdin — no network, no auth, just jq.
# Requires Claude Code v2.1.80+ (when rate_limits was added to statusline stdin).

set -uo pipefail

input=$(cat)

model=$(printf '%s' "$input"      | jq -r '.model.display_name // .model.id // "Claude"')
five_pct=$(printf '%s' "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(printf '%s' "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
ctx_pct=$(printf '%s' "$input"    | jq -r '.context_window.used_percentage // empty')
ctx_size=$(printf '%s' "$input"   | jq -r '.context_window.context_window_size // empty')

# Color thresholds: green <50, yellow >=50, orange >=70, red >=90
colorize() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 90)); then printf '\033[31m'        # red
  elif ((pct >= 70)); then printf '\033[38;5;208m'  # orange
  elif ((pct >= 50)); then printf '\033[33m'        # yellow
  else                     printf '\033[32m'        # green
  fi
}
reset_color() { printf '\033[0m'; }

fmt_time() {
  local epoch=$1
  [[ -z "$epoch" ]] && return
  date -r "$epoch" "+%-I:%M%p" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

# Five-step Unicode circle that fills as percentage rises.
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

# Compact size: 1000000 -> 1M, 200000 -> 200k.
fmt_size() {
  local n=$1
  [[ -z "$n" ]] && return
  if   ((n >= 1000000)); then printf '%dM' $((n / 1000000))
  elif ((n >= 1000));    then printf '%dk' $((n / 1000))
  else                        printf '%d' "$n"
  fi
}

# Show time if the reset is today, otherwise the lowercase weekday (e.g. "fri").
fmt_when() {
  local epoch=$1
  [[ -z "$epoch" ]] && return
  if [[ "$(date -r "$epoch" "+%Y-%m-%d" 2>/dev/null)" == "$(date "+%Y-%m-%d")" ]]; then
    fmt_time "$epoch"
  else
    date -r "$epoch" "+%a" 2>/dev/null | tr '[:upper:]' '[:lower:]'
  fi
}

segments=()
segments+=("$(printf '\033[1m%s\033[0m' "$model")")

if [[ -n "$five_pct" ]]; then
  pct=${five_pct%.*}
  segments+=("$(colorize "$five_pct")5h: ${pct}%$(reset_color) (→$(fmt_time "$five_reset"))")
fi

if [[ -n "$week_pct" ]]; then
  pct=${week_pct%.*}
  segments+=("$(colorize "$week_pct")week: ${pct}%$(reset_color) (→$(fmt_when "$week_reset"))")
fi

if [[ -n "$ctx_pct" ]]; then
  pct=${ctx_pct%.*}
  size_label=""
  [[ -n "$ctx_size" ]] && size_label=" of $(fmt_size "$ctx_size")"
  segments+=("$(colorize "$ctx_pct")$(ctx_circle "$ctx_pct") ${pct}%${size_label}$(reset_color)")
fi

if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
  segments+=("usage data pending - make a request")
fi

sep=" │ "
out=""
for s in "${segments[@]}"; do
  [[ -n "$out" ]] && out+="$sep"
  out+="$s"
done
printf '%b' "$out"
