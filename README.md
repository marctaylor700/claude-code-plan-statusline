# claude-code-plan-statusline

A tiny Claude Code statusline that shows my **actual plan rate-limit usage** - the same numbers `/usage` shows, but always visible at the bottom of the terminal.

![statusline screenshot](screenshot.png)

Reading left to right:

- **Model name** in bold — whatever Claude Code is calling the active model (e.g. `Opus 4.7 (1M context)`).
- **`5h: 14% (→11:00am)`** — your 5-hour rolling plan window and when it resets (local time).
- **`week: 47% (→thu)`** — your 7-day rolling plan window. Shows the time if the reset is today, the lowercase weekday otherwise, so you can tell at a glance whether the limit comes back today or in a few days.
- **`○ 6% of 1M`** — context-window fill for *the current chat*. This is **not** a plan limit. It's how much of the model's working memory this conversation has consumed (6% of 1,000,000 tokens here). It grows monotonically as the chat gets longer; there's no time-based reset — starting a new chat is what clears it. The circle (`○ ◔ ◑ ◕ ●`) is a five-step visual of the same percentage, mostly so you can spot the trend without reading the number.

All three percentages share the same color scale: green → yellow → orange → red as they climb.

## Themes

Four themes ship in the box. Pick one by creating `~/.claude/plan-statusline.conf`:

```
theme=hearth
```

No restart needed — the statusline reads the config on every refresh, so the new theme shows up within a few seconds.

| Theme    | What it looks like                                                                    |
|----------|---------------------------------------------------------------------------------------|
| `default`| Basic ANSI colors, pipe separators, single circle on context. Bold model name. |
| `hearth` | Warm amber, restrained. Bold-amber model name; tier color stays silent until 70% (orange) / 90% (red). Dim italic reset times. |
| `glow`   | Pink neon arcade. Bold-magenta model name; mint→pink→magenta→red tier ramp; italic rose halo on reset times. |
| `scrubs` | Clinical teal vitals monitor. Bold bright-teal model name; teal→bright→amber→red tier ramp like a patient monitor; soft light-teal halo on reset times. |

The model name renders in each theme's solid color. At 100% usage (plan limits only) it dims as part of the easter-egg state. It's static, not animated — Claude Code repaints the statusline at most once per second, far too coarse for smooth motion.

If the file is missing or the theme name is unrecognized, the script falls back to `default` — your prior install keeps working untouched.

### Just ask Claude Code

You don't have to edit anything by hand. Once this statusline is installed, ask Claude Code in plain English:

- *"switch my statusline to glow"* / *"go back to the default theme"*
- *"make me a new statusline theme — ocean blues, calm"*

It edits `~/.claude/plan-statusline.conf` (or adds a new render function to the script) for you, and since the statusline re-reads on every refresh, the change appears within a few seconds — no restart required.

## Why this exists

I'm on a Claude Max plan. I wanted a glanceable answer to "how close am I to hitting the limit?" without typing `/usage` every five minutes.

Most "Claude Code statusline" plugins show **API-equivalent dollar cost** - they multiply your token counts by Anthropic's pay-per-use API rates. Useful if you're paying for the API. Irrelevant if you're on Pro or Max, where the limit that actually matters is your plan's rate-limit window, not a dollar figure.

The one plugin I found that does show real plan usage works by curl-ing an Anthropic OAuth endpoint every 60 seconds, reading your stored credentials to do it. I didn't want to pipe an unvetted shell script my auth token, so I wrote my own.

## How it works

Since Claude Code v2.1.80, the statusline command receives a JSON blob on stdin with the same data `/usage` shows, plus per-chat context-window stats:

```json
{
  "model": { "display_name": "Opus 4.7" },
  "rate_limits": {
    "five_hour": { "used_percentage": 83, "resets_at": 1746234000 },
    "seven_day": { "used_percentage": 52, "resets_at": 1746500400 }
  },
  "context_window": {
    "used_percentage": 6,
    "context_window_size": 1000000
  }
}
```

The script reads that with `jq`, picks the percentages and reset epochs, color-formats them, and prints. No network. No auth. One data-driven renderer feeds every theme.

The `rate_limits` field only appears for Pro/Max subscribers, and only after the first API response in a session. Before then the script prints `usage data pending - make a request`.

### On Enterprise / managed plans

Managed and Enterprise deployments don't get a `rate_limits` block at all — there are no rolling plan windows to show. Instead of leaving the statusline blank, the script auto-detects this and falls back to a **session dashboard** built from the data those payloads *do* carry:

```
Opus 4.8 (1M context) │ $1.01 │ 2m16s │ +1/-0 │ 63k↑ 248↓ │ ○ 6% of 1M
```

Reading left to right: **session cost** (API-equivalent USD, `cost.total_cost_usd`), **wall-clock duration**, **lines changed**, **tokens in ↑ / out ↓**, and the same context circle. Cost carries the green→red tier scale (green `<$2`, yellow `≥$2`, orange `≥$5`, red `≥$10` — tunable constants in `cost_tier_color`); the rest are informational and render dimmed in each theme. Detection is automatic and needs no config: if rate limits are present you get the `5h`/`week` view above, otherwise the dashboard. The same script serves both.

## Install

### Easiest: let Claude Code install it for you

Open any Claude Code session and paste this prompt:

```
Please install the plan-statusline from https://github.com/blazemalan/claude-code-plan-statusline for me. Specifically:

1. Download https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.sh to ~/.claude/hooks/plan-statusline.sh and make it executable.
2. Add a "statusLine" entry to ~/.claude/settings.json so it runs `bash ~/.claude/hooks/plan-statusline.sh`. Preserve all existing keys in that file.
3. Make sure jq is installed (brew install jq if it isn't).
```

That's it. Claude Code will do the file work and the settings edit, ask for permission as it goes, and tell you when it's ready.

### Manual install

If you'd rather do it yourself:

```bash
mkdir -p ~/.claude/hooks
curl -fsSL https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.sh \
  -o ~/.claude/hooks/plan-statusline.sh
chmod +x ~/.claude/hooks/plan-statusline.sh
```

Then add this to `~/.claude/settings.json` (merge with whatever's already there):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/hooks/plan-statusline.sh"
  }
}
```

Start a new Claude Code session, make a request, and the bars appear.

## Requirements

- **macOS, Linux, or WSL** (the script handles both BSD `date -r` and GNU `date -d @`)
- Claude Code v2.1.80 or later
- `jq` (preinstalled on macOS; `brew install jq` if missing)
- Bash 3.2+

## How I made it

Vibes.

## License

MIT
