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

segments=()
segments+=("$(printf '\033[1m%s\033[0m' "$model")")

if [[ -n "$five_pct" ]]; then
  pct=${five_pct%.*}
  segments+=("$(colorize "$five_pct")5h: ${pct}%$(reset_color) (→$(fmt_time "$five_reset"))")
fi

if [[ -n "$week_pct" ]]; then
  pct=${week_pct%.*}
  segments+=("$(colorize "$week_pct")week: ${pct}%$(reset_color) (→$(fmt_time "$week_reset"))")
fi

if [[ -z "$five_pct" && -z "$week_pct" ]]; then
  segments+=("usage data pending - make a request")
fi

sep=" │ "
out=""
for s in "${segments[@]}"; do
  [[ -n "$out" ]] && out+="$sep"
  out+="$s"
done
printf '%b' "$out"
