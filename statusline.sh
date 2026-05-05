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
# Theme: claude — animated sparkle + inline progress bars + warm palette
# ============================================================================

CL_AMBER='\033[38;5;214m'
CL_GREEN='\033[32m'
CL_ORANGE='\033[38;5;208m'
CL_RED='\033[31m'
CL_DIM_RED='\033[2;31m'
CL_DIM='\033[2m'
CL_DIM_IT='\033[2;3m'
CL_BOLD='\033[1m'
CL_RESET='\033[0m'

# Sparkle frames: cycled by current epoch second so the leading char "twinkles"
# between renders. Six frames, ~6s full cycle.
CL_SPARKLES=('✶' '✷' '✸' '✳' '✴' '✻')

claude_sparkle() {
  local frame=$(( $(date +%s) % ${#CL_SPARKLES[@]} ))
  printf '%s' "${CL_SPARKLES[$frame]}"
}

claude_tier_color() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return
  if   ((pct >= 90)); then printf '%b' "$CL_RED"
  elif ((pct >= 70)); then printf '%b' "$CL_ORANGE"
  elif ((pct >= 50)); then printf '%b' "$CL_AMBER"
  else                     printf '%b' "$CL_GREEN"
  fi
}

# Single fill-circle, colored by tier. Same five-step glyph set as default's ctx circle,
# now used in front of each of the three percentages.
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
    printf '%b%s%b %busage data pending - make a request%b' \
      "$CL_AMBER" "$(claude_sparkle)" "$CL_RESET" "$CL_DIM_IT" "$CL_RESET"
    return
  fi

  local sep
  sep=$(printf '%b  ·  %b' "$CL_DIM" "$CL_RESET")

  # ✳  Opus 4.7
  printf '%b%s%b  %b%s%b' \
    "$CL_AMBER" "$(claude_sparkle)" "$CL_RESET" \
    "$CL_BOLD" "$model" "$CL_RESET"

  if [[ -n "$five_pct" ]]; then
    local pct=${five_pct%.*}
    printf '%b' "$sep"
    printf '%b%s%b 5h %b%d%%%b %b(→%s)%b' \
      "$(claude_tier_color "$five_pct")" "$(claude_circle "$five_pct")" "$CL_RESET" \
      "$(claude_tier_color "$five_pct")" "$pct" "$CL_RESET" \
      "$CL_DIM_IT" "$(fmt_time "$five_reset")" "$CL_RESET"
  fi

  if [[ -n "$week_pct" ]]; then
    local pct=${week_pct%.*}
    printf '%b' "$sep"
    printf '%b%s%b week %b%d%%%b %b(→%s)%b' \
      "$(claude_tier_color "$week_pct")" "$(claude_circle "$week_pct")" "$CL_RESET" \
      "$(claude_tier_color "$week_pct")" "$pct" "$CL_RESET" \
      "$CL_DIM_IT" "$(fmt_when "$week_reset")" "$CL_RESET"
  fi

  if [[ -n "$ctx_pct" ]]; then
    local pct=${ctx_pct%.*}
    local size_label=""
    [[ -n "$ctx_size" ]] && size_label=" of $(fmt_size "$ctx_size")"
    printf '%b' "$sep"
    printf '%b%s%b %b%d%%%b%b%s%b' \
      "$(claude_tier_color "$ctx_pct")" "$(claude_circle "$ctx_pct")" "$CL_RESET" \
      "$(claude_tier_color "$ctx_pct")" "$pct" "$CL_RESET" \
      "$CL_DIM_IT" "$size_label" "$CL_RESET"
  fi
}

# ============================================================================
# Dispatch
# ============================================================================

case "$theme" in
  claude)         render_claude ;;
  default|*)      render_default ;;
esac
