# Enterprise stats fallback — design

## Problem

The statusline is built entirely around plan rate-limit windows: it reads
`.rate_limits.five_hour` and `.rate_limits.seven_day` from the statusline stdin
JSON. That field **only exists for Pro/Max subscribers**.

On a managed / Enterprise plan the captured stdin payload contains no
`rate_limits` block at all:

```json
{
  "model": { "id": "claude-opus-4-8[1m]", "display_name": "Opus 4.8 (1M context)" },
  "cost": { "total_cost_usd": 1.009058, "total_duration_ms": 136020,
            "total_lines_added": 1, "total_lines_removed": 0 },
  "context_window": { "total_input_tokens": 63015, "total_output_tokens": 248,
                      "context_window_size": 1000000, "used_percentage": 6 }
}
```

So `render_line` skips both rate segments and the statusline silently collapses
to `Opus 4.8 (1M context) │ ○ 6% of 1M` — the tool's entire reason for being
(usage at a glance) renders nothing for Enterprise users.

## Goal

Make the **same script** serve both plans automatically. Pro/Max rendering is
unchanged. When rate limits are absent, fall back to an Enterprise dashboard
built from the data Enterprise *does* expose.

## Detection (automatic, no config)

`render_line` branches on whether plan rate limits are present:

1. `five_pct` **or** `week_pct` non-empty → **plan mode** (today's `5h` / `week`
   segments + context). Pro/Max — byte-for-byte unchanged.
2. neither present, but any enterprise metric (`cost_usd` or `ctx_pct`) is →
   **enterprise mode** (the dashboard below).
3. nothing at all → existing `usage data pending - make a request` placeholder.

This is self-correcting: a fresh Pro/Max session that hasn't received its first
API response yet has no rate limits *and* no cost/context, so it shows the
pending placeholder until rate limits arrive — then flips to plan mode.

## Enterprise dashboard layout

```
Opus 4.8 (1M context) │ $1.01 │ 2m16s │ +1/-0 │ 63k↑ 248↓ │ ○ 6% of 1M
```

Each segment renders only if its source data is present (mirrors how the rate
segments are conditional today).

| Segment   | Source field(s)                                          | Format                     | Color                  |
|-----------|----------------------------------------------------------|----------------------------|------------------------|
| Cost      | `cost.total_cost_usd`                                    | `$1.01` (`%.2f`)           | **tier ramp** green→red |
| Duration  | `cost.total_duration_ms`                                 | `45s` / `2m16s` / `1h3m`   | meta (dim/italic)      |
| Lines     | `cost.total_lines_added` / `total_lines_removed`         | `+1/-0`                    | meta                   |
| Tokens    | `context_window.total_input_tokens` / `total_output_tokens` | `63k↑ 248↓` (reuses `fmt_size`) | meta            |
| Context   | `context_window.used_percentage` + `context_window_size` | `○ 6% of 1M`               | unchanged `seg_ctx`    |

### Coloring rationale

Only **cost** gets the green→red tier ramp — it is the closest Enterprise analog
to "how close am I to the limit?", the single color-coded number the original
tool was built around. Duration / lines / tokens are context, not alarms, so
they render through the existing `META` style. That means they come out plain in
`default` and dim-italic in hearth/glow/scrubs automatically — every theme stays
faithful with **zero per-theme code**, because the dashboard is assembled from
the same `paint` / `seg_*` primitives the rate segments use.

### Cost tier thresholds (tunable constants)

Dollars bucket onto the shared `TIER_*` colors:

- calm (green)  `< $2`
- warn (yellow) `>= $2`
- hot (orange)  `>= $5`
- urgent (red)  `>= $10`

Compared on the integer-dollar part to avoid bash float math.

## New helpers

- `fmt_cost` — `printf '$%.2f'` (bash printf supports `%f`).
- `fmt_duration` — ms → `Xs` / `XmYs` / `XhYm`.
- `cost_tier_color` — buckets integer dollars onto `TIER_CALM/WARN/HOT/URGENT`.
- `seg_enterprise` (or inline in `render_line`) — emits the five segments.

`fmt_size` and `seg_ctx` are reused as-is.

## Parsing change

Extend the single `jq` call to additionally emit `total_cost_usd`,
`total_duration_ms`, `total_lines_added`, `total_lines_removed`,
`total_input_tokens`, `total_output_tokens` — all `// ""` for absence, joined
by the same `\x1f` unit separator. Vars grow from 7 to 13.

## Out of scope (YAGNI)

- `effort.level`, `thinking.enabled`, `fast_mode` indicators.
- The 100% easter eggs: there is no plan limit to peg on Enterprise, so the
  model name simply sweeps normally (`limit_pegged` stays false).
- Per-user configurable cost thresholds (constants are tunable in-script; the
  README's "just ask Claude" workflow covers tweaks).

## Testing

- New Enterprise fixture (no `rate_limits`) asserting all five segments render
  across all four themes, and that the cost segment is tier-colored.
- A guard that a `rate_limits` payload still shows `5h`/`week` and **never** the
  cost segment (the two modes are mutually exclusive).
- `fmt_duration` / `fmt_cost` / `cost_tier_color` unit assertions.
- All existing tests must stay green (the `EMPTY` fixture must still show the
  pending placeholder).
```
