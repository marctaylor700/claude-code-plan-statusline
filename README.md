# claude-code-plan-statusline

A tiny Claude Code statusline that shows my **actual plan rate-limit usage** - the same numbers `/usage` shows, but always visible at the bottom of the terminal.

```
Opus 4.7 │ 5h: 83% (→4:20pm) │ week: 52% (→2:00pm)
```

5-hour session bar and 7-day weekly bar, color-coded green → yellow → orange → red as you climb, with reset times in your local timezone.

## Why this exists

I'm on a Claude Max plan. I wanted a glanceable answer to "how close am I to hitting the limit?" without typing `/usage` every five minutes.

Most "Claude Code statusline" plugins show **API-equivalent dollar cost** - they multiply your token counts by Anthropic's pay-per-use API rates. Useful if you're paying for the API. Irrelevant if you're on Pro or Max, where the limit that actually matters is your plan's rate-limit window, not a dollar figure.

The one plugin I found that does show real plan usage works by curl-ing an Anthropic OAuth endpoint every 60 seconds, reading your stored credentials to do it. I didn't want to pipe an unvetted shell script my auth token, so I wrote my own.

## How it works

Since Claude Code v2.1.80, the statusline command receives a `rate_limits` object on stdin:

```json
{
  "model": { "display_name": "Opus 4.7" },
  "rate_limits": {
    "five_hour": { "used_percentage": 83, "resets_at": 1746234000 },
    "seven_day": { "used_percentage": 52, "resets_at": 1746500400 }
  }
}
```

The script reads that with `jq`, picks the percentages and reset epochs, color-formats them, and prints. No network. No auth. ~50 lines of bash.

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

- Claude Code v2.1.80 or later
- `jq` (preinstalled on macOS; `brew install jq` or `apt install jq` if missing)
- Bash 3.2+

## How I made it

Vibes-coded it in a single Claude Code session. I asked Claude to install "that popular plugin that shows usage at the bottom" - it installed [ccusage](https://github.com/ryoppippi/ccusage), which is the most popular one but shows API costs, which is the wrong thing for a plan subscriber. After I pointed out that I wanted *plan* usage and not dollars, Claude found that v2.1.80 added stdin rate-limit data and wrote this script against that spec. The whole thing took one back-and-forth.

The script is ~50 lines, no dependencies beyond `jq`. Fork it, change the colors, change the separator, add your git branch - it's a small enough surface area to make your own.

## License

MIT
