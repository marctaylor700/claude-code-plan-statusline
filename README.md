# claude-code-plan-statusline

A tiny Claude Code statusline that shows my **actual plan rate-limit usage** - the same numbers `/usage` shows, but always visible at the bottom of the terminal.

![statusline screenshot](screenshot.png)

Reading left to right:

- **Model name** in bold — whatever Claude Code is calling the active model (e.g. `Opus 4.7 (1M context)`).
- **`5h: 14% (→11:00am)`** — your 5-hour rolling plan window and when it resets (local time).
- **`week: 47% (→thu)`** — your 7-day rolling plan window. Shows the time if the reset is today, the lowercase weekday otherwise, so you can tell at a glance whether the limit comes back today or in a few days.
- **`○ 6% of 1M`** — context-window fill for *the current chat*. This is **not** a plan limit. It's how much of the model's working memory this conversation has consumed (6% of 1,000,000 tokens here). It grows monotonically as the chat gets longer; there's no time-based reset — starting a new chat is what clears it. The circle (`○ ◔ ◑ ◕ ●`) is a five-step visual of the same percentage, mostly so you can spot the trend without reading the number.

All three percentages share the same color scale: green → yellow → orange → red as they climb.

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

The script reads that with `jq`, picks the percentages and reset epochs, color-formats them, and prints. No network. No auth. ~100 lines of bash.

The `rate_limits` field only appears for Pro/Max subscribers, and only after the first API response in a session. Before then the script prints `usage data pending - make a request`.

## Install

```bash
mkdir -p ~/.claude/hooks
curl -fsSL https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.sh \
  -o ~/.claude/hooks/plan-statusline.sh
chmod +x ~/.claude/hooks/plan-statusline.sh
```

Then add this to `~/.claude/settings.json`:

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

- **macOS** (the script uses BSD `date` syntax — Linux/WSL would need a small tweak in `fmt_time` and `fmt_when`)
- Claude Code v2.1.80 or later
- `jq` (preinstalled on macOS; `brew install jq` if missing)
- Bash 3.2+

## How I made it

Vibes-coded it in a single Claude Code session. I asked Claude to install "that popular plugin that shows usage at the bottom" - it installed [ccusage](https://github.com/ryoppippi/ccusage), which is the most popular one but shows API costs, which is the wrong thing for a plan subscriber. After I pointed out that I wanted *plan* usage and not dollars, Claude found that v2.1.80 added stdin rate-limit data and wrote this script against that spec. The whole thing took one back-and-forth.

The script is ~100 lines, no dependencies beyond `jq`. Fork it, change the colors, change the separator, add your git branch - it's a small enough surface area to make your own.

## License

MIT
