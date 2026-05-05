#!/usr/bin/env bash
# Claude Code statusline that shows plan rate-limit usage (5-hour session + 7-day weekly).
# Reads Claude Code's statusline JSON from stdin — no network, no auth, just jq.
# Requires Claude Code v2.1.80+ (when rate_limits was added to statusline stdin).
#
# Theme selection: ~/.claude/plan-statusline.conf, e.g.:
#   theme=claude   # progress bars, animated sparkle, warm palette
#   theme=default  # today's look (default if file missing)

set -uo pipefail

input=$(cat)

# --- Config: read theme from ~/.claude/plan-statusline.conf if present ---
theme=default
config_file="${HOME}/.claude/plan-statusline.conf"
if [[ -f "$config_file" ]]; then
  while IFS='=' read -r key value; do
    # strip surrounding whitespace and quotes
    key=${key// /}
    value=${value// /}
    value=${value%\"}; value=${value#\"}
    case "$key" in
      theme) [[ -n "$value" ]] && theme="$value" ;;
    esac
  done < "$config_file"
fi

# --- Parse stdin JSON (one jq call into 7 vars via @tsv) ---
IFS=$'\t' read -r model five_pct five_reset week_pct week_reset ctx_pct ctx_size < <(
  printf '%s' "$input" | jq -r '[
    .model.display_name // .model.id // "Claude",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at // "",
    .context_window.used_percentage // "",
    .context_window.context_window_size // ""
  ] | @tsv'
)

# --- Shared helpers (used by all themes) ---

reset_color() { printf '\033[0m'; }

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

# ============================================================================
# Theme: default — today's look (preserved exactly)
# ============================================================================

default_color() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 90)); then printf '\033[31m'
  elif ((pct >= 70)); then printf '\033[38;5;208m'
  elif ((pct >= 50)); then printf '\033[33m'
  else                     printf '\033[32m'
  fi
}

default_circle() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 88)); then printf '●'
  elif ((pct >= 63)); then printf '◕'
  elif ((pct >= 38)); then printf '◑'
  elif ((pct >= 13)); then printf '◔'
  else                     printf '○'
  fi
}

render_default() {
  local segments=()
  segments+=("$(printf '\033[1m%s\033[0m' "$model")")

  if [[ -n "$five_pct" ]]; then
    local pct=${five_pct%.*}
    segments+=("$(default_color "$five_pct")5h: ${pct}%$(reset_color) (→$(fmt_time "$five_reset"))")
  fi

  if [[ -n "$week_pct" ]]; then
    local pct=${week_pct%.*}
    segments+=("$(default_color "$week_pct")week: ${pct}%$(reset_color) (→$(fmt_when "$week_reset"))")
  fi

  if [[ -n "$ctx_pct" ]]; then
    local pct=${ctx_pct%.*}
    local size_label=""
    [[ -n "$ctx_size" ]] && size_label=" of $(fmt_size "$ctx_size")"
    segments+=("$(default_color "$ctx_pct")$(default_circle "$ctx_pct") ${pct}%${size_label}$(reset_color)")
  fi

  if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
    segments+=("usage data pending - make a request")
  fi

  local sep=" │ "
  local out=""
  local s
  for s in "${segments[@]}"; do
    [[ -n "$out" ]] && out+="$sep"
    out+="$s"
  done
  printf '%b' "$out"
}

# ============================================================================
# Theme: claude — Powerline-style colored "pills"
# Each segment is a colored background block with bright-white text on top.
# Tier shows in the bg color of each percentage pill (calm green → urgent red).
# Animated sparkle prefixes the model pill and twinkles between renders.
# ============================================================================

# Background colors (256-color)
CL_BG_AMBER='\033[48;5;94m'    # dark amber for the model pill
CL_BG_GREEN='\033[48;5;22m'    # calm: dark green
CL_BG_OLIVE='\033[48;5;100m'   # warning: olive
CL_BG_ORANGE='\033[48;5;166m'  # hot: orange
CL_BG_RED='\033[48;5;88m'      # urgent: dark red

CL_FG_WHITE='\033[97m'         # bright white text
CL_BOLD='\033[1m'
CL_RESET='\033[0m'

# Sparkle frames: cycled by current epoch second so the leading char "twinkles"
# between renders. Six frames; one rotates per second of wall-clock time.
CL_SPARKLES=('✶' '✷' '✸' '✳' '✴' '✻')

claude_sparkle() {
  local frame=$(( $(date +%s) % ${#CL_SPARKLES[@]} ))
  printf '%s' "${CL_SPARKLES[$frame]}"
}

# Tier background for a percentage pill.
claude_tier_bg() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 90)); then printf '%b' "$CL_BG_RED"
  elif ((pct >= 70)); then printf '%b' "$CL_BG_ORANGE"
  elif ((pct >= 50)); then printf '%b' "$CL_BG_OLIVE"
  else                     printf '%b' "$CL_BG_GREEN"
  fi
}

# Five-step fill circle (drawn in white on the pill's bg).
claude_circle() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 88)); then printf '●'
  elif ((pct >= 63)); then printf '◕'
  elif ((pct >= 38)); then printf '◑'
  elif ((pct >= 13)); then printf '◔'
  else                     printf '○'
  fi
}

render_claude() {
  if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
    printf '%b%b %s usage data pending - make a request %b' \
      "$CL_BG_AMBER" "$CL_FG_WHITE" "$(claude_sparkle)" "$CL_RESET"
    return
  fi

  local gap="  "  # space between pills (renders in default bg)

  # Model pill: amber bg, bold white text, animated sparkle prefix.
  printf '%b%b %s %b%s %b' \
    "$CL_BG_AMBER" "$CL_FG_WHITE" "$(claude_sparkle)" \
    "$CL_BOLD" "$model" "$CL_RESET"

  if [[ -n "$five_pct" ]]; then
    local pct=${five_pct%.*}
    printf '%s%b%b %s 5h %d%% →%s %b' \
      "$gap" \
      "$(claude_tier_bg "$five_pct")" "$CL_FG_WHITE" \
      "$(claude_circle "$five_pct")" "$pct" \
      "$(fmt_time "$five_reset")" "$CL_RESET"
  fi

  if [[ -n "$week_pct" ]]; then
    local pct=${week_pct%.*}
    printf '%s%b%b %s week %d%% →%s %b' \
      "$gap" \
      "$(claude_tier_bg "$week_pct")" "$CL_FG_WHITE" \
      "$(claude_circle "$week_pct")" "$pct" \
      "$(fmt_when "$week_reset")" "$CL_RESET"
  fi

  if [[ -n "$ctx_pct" ]]; then
    local pct=${ctx_pct%.*}
    local size_label=""
    [[ -n "$ctx_size" ]] && size_label=" / $(fmt_size "$ctx_size")"
    printf '%s%b%b %s ctx %d%%%s %b' \
      "$gap" \
      "$(claude_tier_bg "$ctx_pct")" "$CL_FG_WHITE" \
      "$(claude_circle "$ctx_pct")" "$pct" \
      "$size_label" "$CL_RESET"
  fi
}

# ============================================================================
# Dispatch
# ============================================================================

case "$theme" in
  claude)         render_claude ;;
  default|*)      render_default ;;
esac
