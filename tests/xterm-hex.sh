#!/usr/bin/env bash
# Print sRGB hex for one or more xterm 256-color cube indices.
# Useful for keeping bash escape codes (\033[...;5;N m) in sync with the
# preview's CSS hex values when designing new themes.
#
#   ./tests/xterm-hex.sh 199 197 41
#   199 → #ff00af
#   197 → #ff005f
#    41 → #00d75f
#
# With no arguments, prints the indices currently used by each theme.

set -euo pipefail

steps=(0 95 135 175 215 255)

cube_hex() {
  local n=$1
  if (( n < 16 || n >= 232 )); then
    printf 'cube-only (16-231): %s\n' "$n" >&2
    return 1
  fi
  local cube=$((n - 16))
  local r=${steps[$((cube / 36))]}
  local g=${steps[$(((cube / 6) % 6))]}
  local b=${steps[$((cube % 6))]}
  printf '#%02x%02x%02x' "$r" "$g" "$b"
}

if (( $# > 0 )); then
  for n in "$@"; do
    printf '%3d → %s\n' "$n" "$(cube_hex "$n")"
  done
  exit 0
fi

printf 'glow:\n'
for n in 41 175 197 199 205; do
  printf '  %3d → %s\n' "$n" "$(cube_hex "$n")"
done

printf '\nhearth:\n'
for n in 196 208 214; do
  printf '  %3d → %s\n' "$n" "$(cube_hex "$n")"
done
