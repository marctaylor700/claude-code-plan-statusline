#!/usr/bin/env bash
# Claude Code statusline that shows plan rate-limit usage (5-hour session + 7-day weekly).
# Reads Claude Code's statusline JSON from stdin — no network, no auth, just jq.
# Requires Claude Code v2.1.80+ (when rate_limits was added to statusline stdin).
#
# Themes: select via ~/.claude/plan-statusline.conf, e.g.:
#   theme=default   # today's look (the safe one)
#   theme=hearth    # warm amber, pulsing sparkle, model-name shimmer
#   theme=pulse     # colored "pill" segments, tier as background
#   theme=glow      # bold bright neon-style, animated sparkle
# Missing or invalid theme → default.

set -uo pipefail

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

# ============================================================================
# Shared helpers (used by every theme)
# ============================================================================

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

# Sparkle frames pulse small ↔ large so the change between renders is dramatic
# (a dot turning into a star is unmistakable, even at slow refresh cadence).
SPARKLES=('·' '✦' '✶' '✦')
sparkle_now() {
  local frame=$(( $(date +%s) % ${#SPARKLES[@]} ))
  printf '%s' "${SPARKLES[$frame]}"
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
    segments+=("$(default_color "$ctx_pct")$(ctx_circle "$ctx_pct") ${pct}%${size_label}$(reset_color)")
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
# Theme: hearth — restrained warm
#   • pulsing sparkle (· ↔ ✶) prefixes the model name
#   • shimmer: one character of the model name is bolded per render, position
#     rotates per second so the bright char "drifts" across the name
#   • amber glyphs, dim italic reset times
#   • tier color only kicks in for warn (orange) and urgent (bold red)
# ============================================================================

H_AMBER='\033[38;5;214m'    # warm amber — visible on light & dark
H_DIM='\033[2m'             # dim attribute — adapts to terminal bg
H_DIM_IT='\033[2;3m'        # dim italic — adapts
H_ORANGE='\033[38;5;208m'   # warning
H_RED='\033[1;38;5;196m'    # bold red, urgent
H_BOLD='\033[1m'
H_NOBOLD='\033[22m'
H_RESET='\033[0m'

# Body text uses the terminal's default foreground so the theme reads on
# both light and dark backgrounds. Tier colors only kick in for warn/urgent.
hearth_tier_fg() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && return  # empty = no color = terminal default
  if   ((pct >= 90)); then printf '%b' "$H_RED"
  elif ((pct >= 70)); then printf '%b' "$H_ORANGE"
  fi
  # else: silent → text renders in default fg
}

# Render TEXT with one character bolded; the bold position rotates per second
# so a "shimmer" appears to drift across the text between renders. No color
# applied — the terminal's default fg carries it on both light & dark bg.
hearth_shimmer() {
  local text=$1
  local n=${#text}
  (( n == 0 )) && { printf '%s' "$text"; return; }
  local pos=$(( $(date +%s) % n ))
  local i char
  for ((i=0; i<n; i++)); do
    char="${text:i:1}"
    if (( i == pos )); then
      printf '%b%s%b' "$H_BOLD" "$char" "$H_NOBOLD"
    else
      printf '%s' "$char"
    fi
  done
}

render_hearth() {
  if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
    printf '%b%s%b %busage data pending - make a request%b' \
      "$H_AMBER" "$(sparkle_now)" "$H_RESET" "$H_DIM_IT" "$H_RESET"
    return
  fi

  local sep
  sep=$(printf '%b · %b' "$H_DIM" "$H_RESET")

  printf '%b%s%b %s' "$H_AMBER" "$(sparkle_now)" "$H_RESET" "$(hearth_shimmer "$model")"

  if [[ -n "$five_pct" ]]; then
    local pct=${five_pct%.*}
    printf '%b' "$sep"
    printf '%b%s%b 5h %b%d%%%b %b(→%s)%b' \
      "$H_AMBER" "$(ctx_circle "$five_pct")" "$H_RESET" \
      "$(hearth_tier_fg "$five_pct")" "$pct" "$H_RESET" \
      "$H_DIM_IT" "$(fmt_time "$five_reset")" "$H_RESET"
  fi

  if [[ -n "$week_pct" ]]; then
    local pct=${week_pct%.*}
    printf '%b' "$sep"
    printf '%b%s%b week %b%d%%%b %b(→%s)%b' \
      "$H_AMBER" "$(ctx_circle "$week_pct")" "$H_RESET" \
      "$(hearth_tier_fg "$week_pct")" "$pct" "$H_RESET" \
      "$H_DIM_IT" "$(fmt_when "$week_reset")" "$H_RESET"
  fi

  if [[ -n "$ctx_pct" ]]; then
    local pct=${ctx_pct%.*}
    local size_label=""
    [[ -n "$ctx_size" ]] && size_label=" of $(fmt_size "$ctx_size")"
    printf '%b' "$sep"
    printf '%b%s%b %b%d%%%b%b%s%b' \
      "$H_AMBER" "$(ctx_circle "$ctx_pct")" "$H_RESET" \
      "$(hearth_tier_fg "$ctx_pct")" "$pct" "$H_RESET" \
      "$H_DIM_IT" "$size_label" "$H_RESET"
  fi
}

# ============================================================================
# Theme: pulse — colored pills (Powerline-style)
#   • each segment is a rounded background-colored block with dark text
#   • amber pill for the model; tier-colored pills for usage segments
#   • animated sparkle inside the model pill
# ============================================================================

# Each tier has TWO bg colors: bright (filled portion of pill) and dim (empty
# portion). The pill becomes its own progress bar — the bright/dim split happens
# at the percentage threshold inside each tier-colored pill.
P_BG_AMBER='\033[48;5;214m'        # amber, model pill (no fill split — solid)
P_BG_GREEN='\033[48;5;40m';      P_BG_GREEN_DIM='\033[48;5;22m'
P_BG_GOLD='\033[48;5;220m';      P_BG_GOLD_DIM='\033[48;5;100m'
P_BG_ORANGE='\033[48;5;208m';    P_BG_ORANGE_DIM='\033[48;5;130m'
P_BG_RED='\033[48;5;196m';       P_BG_RED_DIM='\033[48;5;88m'

P_FG_DARK='\033[38;5;232m'    # near-black, used on bright bg
P_FG_LIGHT='\033[38;5;255m'   # near-white, used on dim bg
P_BOLD='\033[1m'
P_NOBOLD='\033[22m'
P_RESET='\033[0m'

# Pick (bright, dim) bg pair for a tier; outputs "bright|dim".
pulse_tier_pair() {
  local pct=${1%.*}
  if   ((pct >= 90)); then printf '%s|%s' "$P_BG_RED"    "$P_BG_RED_DIM"
  elif ((pct >= 70)); then printf '%s|%s' "$P_BG_ORANGE" "$P_BG_ORANGE_DIM"
  elif ((pct >= 50)); then printf '%s|%s' "$P_BG_GOLD"   "$P_BG_GOLD_DIM"
  else                     printf '%s|%s' "$P_BG_GREEN"  "$P_BG_GREEN_DIM"
  fi
}

# Render TEXT as a "filled" pill: first <pct%> of characters use bright bg + dark
# fg, the rest use dim bg + light fg. The pill's own width is the progress bar.
render_filled_pill() {
  local text=$1 pct=$2 bg_bright=$3 bg_dim=$4
  local total=${#text}
  (( total < 1 )) && return
  local filled=$(( pct * total / 100 ))
  (( filled > total )) && filled=total
  (( filled < 0 )) && filled=0
  local left="${text:0:filled}"
  local right="${text:filled}"
  printf '%b%b%s%b%b%s%b' \
    "$bg_bright" "$P_FG_DARK"  "$left" \
    "$bg_dim"    "$P_FG_LIGHT" "$right" \
    "$P_RESET"
}

render_pulse() {
  if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
    printf '%b%b %s usage data pending - make a request %b' \
      "$P_BG_AMBER" "$P_FG_DARK" "$(sparkle_now)" "$P_RESET"
    return
  fi

  local gap=" "

  # Model pill: solid amber (no fill split — model isn't a usage metric).
  printf '%b%b %s %b%s%b %b' \
    "$P_BG_AMBER" "$P_FG_DARK" "$(sparkle_now)" \
    "$P_BOLD" "$model" "$P_NOBOLD" "$P_RESET"

  if [[ -n "$five_pct" ]]; then
    local pct=${five_pct%.*} pair bright dim pill
    pair=$(pulse_tier_pair "$five_pct"); bright="${pair%|*}"; dim="${pair#*|}"
    pill=" $(ctx_circle "$five_pct") 5h ${pct}% →$(fmt_time "$five_reset") "
    printf '%s' "$gap"
    render_filled_pill "$pill" "$pct" "$bright" "$dim"
  fi

  if [[ -n "$week_pct" ]]; then
    local pct=${week_pct%.*} pair bright dim pill
    pair=$(pulse_tier_pair "$week_pct"); bright="${pair%|*}"; dim="${pair#*|}"
    pill=" $(ctx_circle "$week_pct") week ${pct}% →$(fmt_when "$week_reset") "
    printf '%s' "$gap"
    render_filled_pill "$pill" "$pct" "$bright" "$dim"
  fi

  if [[ -n "$ctx_pct" ]]; then
    local pct=${ctx_pct%.*} pair bright dim pill size_label=""
    pair=$(pulse_tier_pair "$ctx_pct"); bright="${pair%|*}"; dim="${pair#*|}"
    [[ -n "$ctx_size" ]] && size_label=" / $(fmt_size "$ctx_size")"
    pill=" $(ctx_circle "$ctx_pct") ${pct}%${size_label} "
    printf '%s' "$gap"
    render_filled_pill "$pill" "$pct" "$bright" "$dim"
  fi
}

# ============================================================================
# Theme: glow — bold bright neon-style
#   • terminals can't actually render text-shadow halos, so we approximate
#     "glow" via bold weight + the brightest 256-color values in each tier
#   • animated sparkle, dim italic metadata, dim middle-dot separators
# ============================================================================

G_AMBER='\033[1;38;5;214m'  # bold amber — readable on light & dark
G_MODEL='\033[1m'           # bold only — uses terminal default fg, adapts
G_GREEN='\033[1;38;5;34m'   # bold green (medium-saturation, works on both)
G_GOLD='\033[1;38;5;178m'   # bold gold (pure-yellow 226 disappears on white)
G_ORANGE='\033[1;38;5;208m' # bold orange
G_RED='\033[1;38;5;160m'    # bold red (medium — 196 is fine but 160 is calmer)
G_DIM='\033[2m'             # plain dim — adapts to bg
G_DIM_IT='\033[2;3m'        # dim italic — adapts
G_RESET='\033[0m'

glow_tier_fg() {
  local pct=${1%.*}
  [[ -z "$pct" ]] && { printf '%b' "$G_GREEN"; return; }
  if   ((pct >= 90)); then printf '%b' "$G_RED"
  elif ((pct >= 70)); then printf '%b' "$G_ORANGE"
  elif ((pct >= 50)); then printf '%b' "$G_GOLD"
  else                     printf '%b' "$G_GREEN"
  fi
}

render_glow() {
  if [[ -z "$ctx_pct" && -z "$five_pct" && -z "$week_pct" ]]; then
    printf '%b%s%b %busage data pending - make a request%b' \
      "$G_AMBER" "$(sparkle_now)" "$G_RESET" "$G_DIM_IT" "$G_RESET"
    return
  fi

  local sep
  sep=$(printf '%b · %b' "$G_DIM" "$G_RESET")

  printf '%b%s%b %b%s%b' \
    "$G_AMBER" "$(sparkle_now)" "$G_RESET" \
    "$G_MODEL" "$model" "$G_RESET"

  if [[ -n "$five_pct" ]]; then
    local pct=${five_pct%.*}
    printf '%b' "$sep"
    printf '%b%s 5h %d%%%b %b(→%s)%b' \
      "$(glow_tier_fg "$five_pct")" "$(ctx_circle "$five_pct")" "$pct" "$G_RESET" \
      "$G_DIM_IT" "$(fmt_time "$five_reset")" "$G_RESET"
  fi

  if [[ -n "$week_pct" ]]; then
    local pct=${week_pct%.*}
    printf '%b' "$sep"
    printf '%b%s week %d%%%b %b(→%s)%b' \
      "$(glow_tier_fg "$week_pct")" "$(ctx_circle "$week_pct")" "$pct" "$G_RESET" \
      "$G_DIM_IT" "$(fmt_when "$week_reset")" "$G_RESET"
  fi

  if [[ -n "$ctx_pct" ]]; then
    local pct=${ctx_pct%.*}
    local size_label=""
    [[ -n "$ctx_size" ]] && size_label=" of $(fmt_size "$ctx_size")"
    printf '%b' "$sep"
    printf '%b%s %d%%%b%b%s%b' \
      "$(glow_tier_fg "$ctx_pct")" "$(ctx_circle "$ctx_pct")" "$pct" "$G_RESET" \
      "$G_DIM_IT" "$size_label" "$G_RESET"
  fi
}

# ============================================================================
# Dispatch
# ============================================================================

case "$theme" in
  hearth)         render_hearth ;;
  pulse)          render_pulse ;;
  glow)           render_glow ;;
  default|*)      render_default ;;
esac
