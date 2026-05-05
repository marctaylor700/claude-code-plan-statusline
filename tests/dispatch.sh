#!/usr/bin/env bash
# Snapshot test for theme dispatch in statusline.sh.
# Confirms each theme renders, unknown names fall through to default,
# and the empty-state placeholder appears when rate_limits is absent.

set -euo pipefail

cd "$(dirname "$0")/.."

SAMPLE='{"model":{"display_name":"Opus 4.7"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1746234000},"seven_day":{"used_percentage":78,"resets_at":1746500400}},"context_window":{"used_percentage":15,"context_window_size":1000000}}'
EMPTY='{"model":{"display_name":"Opus 4.7"}}'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"

ESC=$(printf '\033')

# Strip CSI escape sequences (\033[...m) so substring matching works across
# themes that interleave ANSI codes inside the model name (e.g. hearth's
# shimmer bolds one character per second, breaking the literal "Opus 4.7").
strip_ansi() { sed -E "s/${ESC}\[[0-9;]*m//g"; }

assert_renders() {
  local theme=$1 input=$2 expect=$3
  if [[ -n "$theme" ]]; then
    printf 'theme=%s\n' "$theme" > "$TMP/.claude/plan-statusline.conf"
  else
    rm -f "$TMP/.claude/plan-statusline.conf"
  fi
  local raw plain
  raw=$(echo "$input" | HOME="$TMP" bash statusline.sh)
  plain=$(printf '%s' "$raw" | strip_ansi)
  if [[ "$plain" != *"$expect"* ]]; then
    printf 'FAIL theme=%-8s expected substring %q\n  got: %s\n' \
      "${theme:-<none>}" "$expect" "$plain" >&2
    return 1
  fi
  printf 'PASS theme=%-8s (matched %q)\n' "${theme:-<none>}" "$expect"
}

# Every declared theme renders the model name
assert_renders default "$SAMPLE" "Opus 4.7"
assert_renders hearth  "$SAMPLE" "Opus 4.7"
assert_renders glow    "$SAMPLE" "Opus 4.7"

# Removed/unknown theme name silently falls through to default
# (backward compat for users with theme=pulse in their config)
assert_renders pulse   "$SAMPLE" "Opus 4.7"
assert_renders zzz     "$SAMPLE" "Opus 4.7"

# No config file → default theme via case-statement catch-all
assert_renders ""      "$SAMPLE" "Opus 4.7"

# Empty rate_limits → "usage data pending" placeholder text
assert_renders default "$EMPTY"  "usage data pending"
assert_renders hearth  "$EMPTY"  "usage data pending"
assert_renders glow    "$EMPTY"  "usage data pending"

echo
echo "All dispatch tests passed."
