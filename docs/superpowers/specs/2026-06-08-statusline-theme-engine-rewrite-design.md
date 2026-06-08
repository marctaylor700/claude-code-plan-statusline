# Statusline theme engine rewrite — design

**Date:** 2026-06-08
**File touched:** `statusline.sh` (+ `tests/`, `README.md`)
**Type:** architecture rewrite (behavior near-faithful; one new visual effect)

## Goal

Replace the four near-identical `render_<theme>` functions (~300 duplicated
lines) with **one data-driven renderer**. Each theme becomes a small block of
data (palette, glyphs, flags, easter-egg strings) that a single `render_line`
consumes. The four current looks (`default`, `hearth`, `glow`, `scrubs`) are
reproduced faithfully — with three deliberate, requested deltas (below).

New requested capability: a **gradient sweep** on the model name (like Claude
Code's "Catapulting…" shimmer) — a bright band that sweeps left→right across the
characters, advancing smoothly with real time.

## Non-goals (YAGNI)

- No external/drop-in theme files (sourcing arbitrary `.sh` is a security +
  complexity cost; 4 built-ins don't need it). Noted as a possible future.
- No new themes. Same four names ship.
- No bash 4+ features. macOS ships **bash 3.2** — no associative arrays, no
  `$EPOCHREALTIME` guaranteed. The design stays 3.2-safe.

## Constraints

- **bash 3.2 + BSD `date`** (macOS default) must work with zero extra deps.
  Indexed arrays only — no `declare -A`.
- The script runs **fresh per refresh** (each statusline repaint = new process).
  No state persists between frames except wall-clock time.
- `jq` is the only hard dependency (already required).
- Existing `tests/dispatch.sh` must keep passing.
- Backward compat: unknown/removed theme names still fall through to `default`.

## Architecture

```
statusline.sh
├─ stdin parse (jq → 7 vars)            [unchanged]
├─ config read (theme name)             [unchanged]
├─ shared helpers
│   ├─ date_fmt / fmt_time / fmt_size / fmt_when   [unchanged]
│   ├─ ctx_circle                                   [unchanged]
│   ├─ limit_pegged                                 [unchanged]
│   ├─ now_ms()         [NEW] best-available ms clock, fallback to seconds
│   └─ sweep(text)      [NEW] gradient band over text, theme palette
├─ theme loaders (set globals, no rendering)
│   ├─ theme_default()  theme_hearth()  theme_glow()  theme_scrubs()
├─ render_line()        [NEW] the ONE renderer; reads theme globals
└─ dispatch: case $theme → theme_X (load) → render_line
```

The old `render_default/hearth/glow/scrubs`, the per-theme `*_tier_fg`,
`*_color`, `hearth_shimmer`, `hearth_spark`, `*_burnout/gameover/flatline`, the
`SPARKLES`/`HEARTH_SMOKE`/`SCRUBS_BEAT` arrays and `sparkle_now` are all
**deleted** — their behavior folds into data + the shared renderer/sweep.

## Theme data schema

Each `theme_X()` sets these globals (indexed arrays + scalars; empty string is a
meaningful value = "use terminal default fg"):

| Global | Meaning |
|---|---|
| `TIER_CALM` `TIER_WARN` `TIER_HOT` `TIER_URGENT` | ANSI body for `<50 / 50–69 / 70–89 / 90+`. Empty = terminal default fg. |
| `SWEEP_RAMP` (array of 3) | `(base mid peak)` ANSI for the moving band. |
| `SEP` `SEP_COLOR` | separator string + its ANSI (empty = plain). |
| `META` | ANSI for reset times / size label. Empty = inherit the segment's tier color. |
| `SEG_CIRCLE` | `1` = circle prefix on 5h/week segments; `0` = none. (Context always shows a circle.) |
| `LABEL_SEP` | between label and value: `":"` (default) or `" "` (others). |
| `EGG_GLYPH` | optional glyph prefix on a pegged segment (ANSI-wrapped). Empty = none. |
| `EGG_MSG_A` `EGG_COLOR_A` | pegged message + color, frame A. |
| `EGG_MSG_B` `EGG_COLOR_B` | frame B. If equal to A → no flash. |
| `EGG_RESET_WORD` | word before the reset time on a pegged segment (`respawn`/`rekindles`/`1UP`/`defib`). |

Thresholds are shared (not per-theme): `urgent ≥90, hot ≥70, warn ≥50, else
calm`. (hearth expresses its "silent until 70" look by setting CALM and WARN to
empty.) Circle thresholds stay in `ctx_circle` (88/63/38/13) unchanged.

### Exact per-theme values

ANSI written as the SGR parameters (the part between `\033[` and `m`).

**default** — basic ANSI, faithful to today.
```
TIER_CALM=32  TIER_WARN=33  TIER_HOT=38;5;208  TIER_URGENT=31
SWEEP_RAMP=( "" 38;5;252 1;38;5;255 )      # plain → grey → bold white band
SEP=" │ "   SEP_COLOR=""                     # plain pipe
META=""                                      # reset/size inherit tier color
SEG_CIRCLE=0   LABEL_SEP=":"                 # "5h: 14%"
EGG_GLYPH=""   EGG_RESET_WORD="respawn"
EGG_MSG_A="100% 💀"  EGG_COLOR_A=31
EGG_MSG_B="100% 💀"  EGG_COLOR_B=31          # equal → no flash
```

**hearth** — warm amber, restrained (calm/warn silent).
```
TIER_CALM=""  TIER_WARN=""  TIER_HOT=38;5;208  TIER_URGENT=1;38;5;196
SWEEP_RAMP=( 38;5;214 38;5;221 1;38;5;230 )  # amber → gold → pale gold
SEP=" · "   SEP_COLOR=2                       # dim middot
META=2;3                                      # dim italic
SEG_CIRCLE=1   LABEL_SEP=" "                  # "◔ 5h 14%"
EGG_GLYPH=2:○  (dim hollow circle)  EGG_RESET_WORD="rekindles"
EGG_MSG_A="burnt out"  EGG_COLOR_A=1;38;5;196
EGG_MSG_B="burnt out"  EGG_COLOR_B=1;38;5;196 # no flash
```
(`EGG_GLYPH` carries its own color; notation `2:○` = render `○` in SGR `2`.)

**glow** — pink neon arcade.
```
TIER_CALM=1;38;5;41  TIER_WARN=1;38;5;205  TIER_HOT=1;38;5;199  TIER_URGENT=1;38;5;197
SWEEP_RAMP=( 1;38;5;205 1;38;5;199 1;38;5;231 )  # pink → magenta → white-hot
SEP=" · "   SEP_COLOR=2
META=3;38;5;175                               # italic rose
SEG_CIRCLE=1   LABEL_SEP=" "
EGG_GLYPH=""   EGG_RESET_WORD="1UP"
EGG_MSG_A="GAME OVER"   EGG_COLOR_A=1;38;5;197
EGG_MSG_B="INSERT COIN" EGG_COLOR_B=1;38;5;199   # flashes
```

**scrubs** — clinical teal vitals monitor.
```
TIER_CALM=38;5;30  TIER_WARN=1;38;5;37  TIER_HOT=38;5;214  TIER_URGENT=1;38;5;196
SWEEP_RAMP=( 38;5;30 38;5;37 1;38;5;159 )    # teal → bright teal → pale cyan
SEP=" · "   SEP_COLOR=2
META=3;38;5;152                               # italic light teal
SEG_CIRCLE=1   LABEL_SEP=" "
EGG_GLYPH=""   EGG_RESET_WORD="defib"
EGG_MSG_A="CODE BLUE"   EGG_COLOR_A=1;38;5;196
EGG_MSG_B="▁▁▁▁▁▁▁▁▁"   EGG_COLOR_B=1;38;5;196   # flashes (text ↔ flat trace)
```

## `render_line()` logic

Pseudocode (consumes theme globals + the 7 parsed vars):

```
# empty state (no rate data at all)
if five_pct, week_pct, ctx_pct all empty:
    print sweep(model) + sep + META-styled "usage data pending - make a request"
    return

out = sweep(model)

seg_rate(label, pct, reset_str):          # for 5h and week
    if pct >= 100: return egg(label, reset_str)
    color = tier_color(pct)
    circle = SEG_CIRCLE ? "ctx_circle(pct) " : ""
    return color + circle + label + LABEL_SEP + " " + pct + "%" + RESET
         + " " + meta_color(color) + "(→" + reset_str + ")" + RESET

seg_ctx(pct, size):                        # context, always circled, no reset/egg
    color = tier_color(pct)
    return color + ctx_circle(pct) + " " + pct + "%" + RESET
         + meta_color(color) + size_label + RESET

append seg_rate("5h", five_pct, fmt_time(five_reset))   if five_pct
append seg_rate("week", week_pct, fmt_when(week_reset))  if week_pct
append seg_ctx(ctx_pct, fmt_size(ctx_size))             if ctx_pct
join with SEP_COLOR+SEP+RESET
```

Helpers inside the renderer:
- `tier_color(pct)` → picks `TIER_*` by shared thresholds; empty = no SGR.
- `meta_color(tier)` → `META` if set, else `tier` (so default's reset/size
  inherit the segment color, matching today).
- `egg(label, reset_str)`:
  ```
  frame = (seconds % 2)
  msg, col = frame ? (EGG_MSG_B, EGG_COLOR_B) : (EGG_MSG_A, EGG_COLOR_A)
  glyph = EGG_GLYPH ? render(EGG_GLYPH)+" " : ""
  return glyph + col + label + LABEL_SEP-or-space + " " + msg + RESET
       + " " + meta_or_plain + "(" + EGG_RESET_WORD + " →" + reset_str + ")" + RESET
  ```
  (default's egg label is `5h:` via LABEL_SEP; glow/scrubs use a space; hearth
  uses a space + the ○ glyph. The reset clause is META-styled for
  hearth/glow/scrubs, plain for default — i.e. `meta_or_plain = META` (empty →
  plain), matching today.)

### Faithfulness check (verified against current code)

- default: no circle on 5h/week, `:` labels, `│` sep, reset/size in tier color,
  💀 egg with plain "(respawn →…)". ✓
- hearth: silent calm/warn (empty tiers), circles, `·` sep, dim-italic meta,
  ○ + "burnt out" + dim-italic "(rekindles →…)". ✓
- glow: mint→pink→magenta→pink-red tiers, circles, italic-rose meta, GAME
  OVER ↔ INSERT COIN flash, "1UP". ✓
- scrubs: teal→bright→amber→red tiers, circles, italic-teal meta, CODE BLUE ↔
  flat-trace flash, "defib". ✓

## Gradient sweep — `sweep(text)`

A bright band moves across `text`, base color elsewhere. Integer math only.

```
sweep(text):
    n = length(text)
    if n == 0: print text; return
    if limit_pegged():                      # DELTA 3: name "dies"
        print SGR(2) + text + RESET         # frozen, dim — no motion
        return
    ms = now_ms()
    period = 2200                            # full traverse ≈ 2.2s (tunable)
    pad = 4
    center = (ms % period) * (n + pad) / period - pad/2   # integer
    for i in 0..n-1:
        d = abs(i - center)
        ramp = SWEEP_RAMP
        sgr = d==0 ? ramp[2] : d==1 ? ramp[1] : ramp[0]   # peak / mid / base
        # Emit an EXPLICIT code for EVERY char so the prior char's color can't
        # bleed forward. Empty base (default theme) → emit reset, not nothing.
        print (sgr ? "\033["+sgr+"m" : "\033[0m") + text[i]
    print RESET
```

- ANSI is interleaved between characters, so **ANSI-stripped output == `text`**.
  This is the test invariant and matches how `strip_ansi` already handles
  hearth's old shimmer.
- Band advances ~1 char per `period/(n+pad)` ms (~150–200 ms) → flows smoothly
  at refresh cadence; degrades to per-char-per-second under the seconds-only
  clock fallback (still animates, just choppier — the accepted tradeoff).
- `base==""` (default theme) → those chars print with no SGR (terminal default),
  only the moving mid/peak band lights up → restrained white highlight.

## Millisecond clock — `now_ms()`

Pick the first available; prefer no-subprocess. Probe cheaply (the chosen method
is used for the rest of the single render).

```
now_ms():
    if $EPOCHREALTIME set (bash5):  echo ${EPOCHREALTIME/./} truncated to ms   # no spawn
    elif date +%s%N is all digits (GNU date): echo (that / 1e6)
    elif have perl:    perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000'
    elif have python3: python3 -c 'import time;print(int(time.time()*1000))'
    else:              echo $(( $(date +%s) * 1000 ))     # per-second fallback
```

Detection is per-render (fresh process), so keep it to simple `command -v` /
pattern checks. On macOS the likely path is `perl` (preinstalled) → one extra
process per repaint (~20–30 ms), accepted. `EPOCHREALTIME`/GNU-date paths spawn
nothing extra.

## Behavior deltas from today (the only intended changes)

1. **Model name sweeps** on every theme (incl. default's restrained band).
   Replaces: default plain-bold, hearth bold-char drift, glow magenta sparkle
   prefix, scrubs heartbeat prefix.
2. **Prefix glyphs removed** (sparkle ·✦✶, heartbeat ·+✚). The swept name is the
   animation now (closest to Claude's spinner).
3. **Pegged name freezes dim** — at 100% the sweep stops and the model name goes
   dim, on top of the existing per-segment easter egg.
4. **Empty-state unified** — every theme prints the (swept) model name +
   `usage data pending - make a request`. Today default shows the model but
   hearth/glow/scrubs don't; this standardizes on showing it.

All other output is byte-faithful to the current themes.

## Testing

- `tests/dispatch.sh` — unchanged assertions still pass (each theme renders the
  model name after ANSI strip; unknown→default; empty→"usage data pending").
- **New** `tests/sweep.sh` — asserts `sweep("Opus 4.8")` ANSI-stripped equals
  `Opus 4.8` exactly (no dropped/duplicated chars), for each theme's ramp, and
  for a 1-char and empty string edge case.
- `tests/xterm-hex.sh` — update the per-theme index lists to the new ramp/tier
  palette so the dev color reference stays accurate.

## Docs

- `README.md` Themes table + descriptions: update to "model name gradient-sweeps
  in the theme's palette" for all four; note default now animates (subtle white
  band); drop the sparkle/heartbeat descriptions. Mention the smooth-clock
  behavior briefly under requirements (optional `perl`/GNU-date for smoothest
  sweep; degrades gracefully).
- Screenshot is static and can't capture motion — leave as-is or note it shows a
  single frame.

## Risk / rollback

- Single file; `git revert` restores the prior version.
- Keep the dispatch `case` + theme names identical → existing installs and
  configs keep working.
- The sweep's integer center math must guard `n+pad` and negative `center`
  (clamp) so a 1–2 char model name can't index out of range.
```
