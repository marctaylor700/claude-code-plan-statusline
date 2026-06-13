# claude-code-plan-statusline

[![tests](https://github.com/blazemalan/claude-code-plan-statusline/actions/workflows/test.yml/badge.svg)](https://github.com/blazemalan/claude-code-plan-statusline/actions/workflows/test.yml)

A tiny [Claude Code](https://www.anthropic.com/claude-code) statusline that keeps your **actual plan rate-limit usage** at the bottom of the terminal — the same numbers `/usage` reports, without typing `/usage`. No network calls, no auth, no dollar-cost guesswork.

![statusline screenshot](screenshot.png)

- **Real plan usage, not dollar cost** — your 5-hour and weekly rate-limit windows and when they reset, read straight from Claude Code's own data.
- **Pro, Max, and Enterprise** — auto-detects your plan: rate-limit windows on Pro/Max, a session dashboard (cost · duration · tokens) on managed/Enterprise plans that have no windows.
- **Per-chat context gauge** — how full the current conversation's context window is, at a glance.
- **Four built-in themes** — switch instantly with no restart, or ask Claude Code to invent a new one.
- **No network, no auth** — reads only the JSON Claude Code already pipes in; never touches your credentials.
- **Portable** — macOS, Linux, WSL, and native Windows. The bash version needs only `jq`; the PowerShell version (`statusline.ps1`) needs **zero installs** (PowerShell 5.1+ built-ins). The two render byte-identical output — a cross-check test diffs them on every fixture.

## Why plan usage, not dollar cost

Most Claude Code statusline plugins show **API-equivalent dollar cost** — your token counts multiplied by Anthropic's pay-per-use API rates. That's useful if you pay for the API, but on Pro or Max it's beside the point: the limit that actually bites is your plan's **rate-limit window**, not a dollar figure.

This statusline shows the window instead — how much of your rolling allowances you've spent and when they reset. It reads that straight from the JSON Claude Code already hands the statusline command, so unlike tools that poll an Anthropic OAuth endpoint with your stored credentials, it makes **no network calls and never reads your auth token**.

## What it shows

Reading the Pro/Max line left to right:

- **Model name** — whatever Claude Code is calling the active model (e.g. `Opus 4.8 (1M context)`), in the active theme's color.
- **`5h: 14% (→11:00am)`** — your 5-hour rolling plan window and when it resets (local time).
- **`week: 47% (→thu)`** — your 7-day rolling window. It shows a clock time when the reset is today and the lowercase weekday otherwise, so you can tell at a glance whether the limit comes back today or in a few days.
- **`○ 6% of 1M`** — context-window fill for *the current chat*. This is **not** a plan limit — it's how much of the model's working memory the conversation has consumed (6% of 1,000,000 tokens here). It only grows as the chat gets longer; starting a new chat clears it. The circle (`○ ◔ ◑ ◕ ●`) is a five-step visual of the same percentage.

All three percentages share one color scale: green → yellow → orange → red as they climb.

On Enterprise/managed plans the layout adapts automatically — see [Enterprise / managed plans](#enterprise--managed-plans).

## Install

### Let Claude Code install it (easiest)

**macOS / Linux / WSL** — open any Claude Code session and paste:

> Please install the plan-statusline from https://github.com/blazemalan/claude-code-plan-statusline for me:
> 1. Download https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.sh to `~/.claude/hooks/plan-statusline.sh` and make it executable.
> 2. Add a `statusLine` entry to `~/.claude/settings.json` that runs `bash ~/.claude/hooks/plan-statusline.sh`, preserving all existing keys.
> 3. Make sure `jq` is installed (`brew install jq` if not).

**Windows (native, nothing to install)** — paste this instead:

> Please install the plan-statusline (Windows PowerShell version) from https://github.com/blazemalan/claude-code-plan-statusline for me:
> 1. Download https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.ps1 to `~/.claude/hooks/plan-statusline.ps1`, preserving its UTF-8 BOM.
> 2. Add a `statusLine` entry to `~/.claude/settings.json` that runs `powershell -NoProfile -ExecutionPolicy Bypass -File <the absolute path to that file, with forward slashes>`, preserving all existing keys.
> Nothing else to install — it's pure PowerShell 5.1+ built-ins.

Claude Code does the file work and the settings edit, asking permission as it goes.

### Manual install — macOS / Linux / WSL

```bash
mkdir -p ~/.claude/hooks
curl -fsSL https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.sh \
  -o ~/.claude/hooks/plan-statusline.sh
chmod +x ~/.claude/hooks/plan-statusline.sh
```

Then merge this into `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/hooks/plan-statusline.sh"
  }
}
```

Start a new Claude Code session and make a request — the statusline appears at the next refresh.

### Manual install — Windows (native PowerShell)

No dependencies: `statusline.ps1` is a line-for-line port of the bash version using only PowerShell 5.1+ built-ins.

**Easiest:** [download the repo as a ZIP](https://github.com/blazemalan/claude-code-plan-statusline/archive/refs/heads/main.zip), extract it, and double-click `install-windows.bat`. It copies the script into place, updates your Claude Code settings (backing them up first), and shows a live preview of your statusline. Done.

**Or by hand** — in a PowerShell window:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\hooks" | Out-Null
Invoke-WebRequest -Uri https://raw.githubusercontent.com/blazemalan/claude-code-plan-statusline/main/statusline.ps1 `
  -OutFile "$env:USERPROFILE\.claude\hooks\plan-statusline.ps1"
```

Then merge this into `%USERPROFILE%\.claude\settings.json`, replacing `YOURNAME` with your Windows username (absolute path, forward slashes — that form works whether Claude Code routes the command through Git Bash, cmd, or PowerShell):

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/YOURNAME/.claude/hooks/plan-statusline.ps1"
  }
}
```

Notes:
- Works on Windows PowerShell 5.1 (preinstalled on Windows 10/11) and PowerShell 7+ (`pwsh`). If you have `pwsh`, you can use it in the command instead — it starts faster.
- If you have **Git Bash** installed, the bash version also works on Windows (`"command": "bash C:/Users/YOURNAME/.claude/hooks/plan-statusline.sh"`), but it needs `jq`. The PowerShell version needs nothing — when in doubt, use it. The two produce identical output.
- The file must stay **UTF-8 with BOM** (it ships that way; `Invoke-WebRequest -OutFile` preserves it). Without the BOM, PowerShell 5.1 garbles the Unicode circle/arrow glyphs.

## Themes

Four themes ship in the box. Select one by creating `~/.claude/plan-statusline.conf` (`%USERPROFILE%\.claude\plan-statusline.conf` on Windows — both scripts read the same file):

```
theme=hearth
```

No restart needed — the statusline re-reads the config on every refresh, so a new theme shows up within a few seconds.

### Disabling color

The statusline honors [`NO_COLOR`](https://no-color.org): set the `NO_COLOR` environment variable to any non-empty value and the line renders as plain text — same glyphs, same layout, no ANSI color. Useful for log capture, screen readers, or minimal terminals. Both the bash and PowerShell versions behave identically.

| Theme     | Look                                                                                                                |
|-----------|---------------------------------------------------------------------------------------------------------------------|
| `default` | Basic ANSI colors, pipe separators, single context circle. Bold model name.                                         |
| `hearth`  | Warm amber, restrained. Bold-amber name; tier color stays silent until 70% (orange) / 90% (red); dim italic reset times. |
| `glow`    | Pink neon arcade. Bold-magenta name; mint→pink→magenta→red tier ramp; italic rose reset times.                      |
| `scrubs`  | Clinical teal vitals monitor. Bold bright-teal name; teal→bright→amber→red ramp; soft light-teal reset times.       |

The model name renders in each theme's solid color (at 100% plan usage it dims, part of the per-theme easter egg). If the config file is missing or names an unknown theme, the statusline falls back to `default`.

### Ask Claude Code to theme it

Once installed, you can change the look in plain English instead of editing files:

- *"switch my statusline to glow"* / *"go back to the default theme"*
- *"make me a new statusline theme — ocean blues, calm"*

Claude Code edits `~/.claude/plan-statusline.conf` (or adds a new render function to the script); the change appears within a few seconds, no restart required.

## Enterprise / managed plans

Managed and Enterprise deployments don't receive a `rate_limits` block — there are no rolling plan windows to show. Rather than render blank, the statusline detects this and falls back to a **session dashboard** built from the data those payloads do carry:

```
Opus 4.8 (1M context) │ $1.01 │ 2m16s │ +1/-0 │ 63k↑ 248↓ │ ○ 6% of 1M
```

Left to right: **session cost** (API-equivalent USD), **wall-clock duration**, **lines changed**, **tokens in ↑ / out ↓**, and the same context circle. Cost carries the green→red scale (green `<$2`, yellow `≥$2`, orange `≥$5`, red `≥$10` — tunable in `cost_tier_color`); the rest render dimmed. Detection is automatic and needs no config: rate limits present → the `5h`/`week` view; absent → the dashboard. One script serves both.

## How it works

Since Claude Code v2.1.80, the statusline command receives a JSON blob on stdin with the same data `/usage` shows, plus per-chat context stats:

```json
{
  "model": { "display_name": "Opus 4.8" },
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

The script parses it with `jq`, picks the percentages and reset epochs, color-formats them, and prints. No network, no auth. One data-driven renderer feeds every theme.

The `rate_limits` field appears only for Pro/Max subscribers, and only after the first API response in a session — until then the statusline shows `usage data pending - make a request`. (Enterprise/managed plans never send it; see [above](#enterprise--managed-plans).)

## Requirements

- Claude Code v2.1.80 or later
- **macOS / Linux / WSL** (`statusline.sh`): Bash 3.2+ and `jq` (preinstalled on macOS; `brew install jq` otherwise). Handles both BSD `date -r` and GNU `date -d @`.
- **Windows** (`statusline.ps1`): Windows PowerShell 5.1 (preinstalled on Windows 10/11) or PowerShell 7+. No other dependencies.

## Development

The renderer is data-driven: each theme is just a set of variables consumed by a single `render_line`; `statusline.ps1` mirrors the same structure function-for-function. The tests are plain Bash / plain PowerShell and need no framework:

```bash
bash tests/unit.sh        # sourceable helpers (formatting, circles, name rendering)
bash tests/dispatch.sh    # theme dispatch + render faithfulness across themes
bash tests/enterprise.sh  # Enterprise fallback + plan/enterprise mode exclusivity
bash tests/robustness.sh  # malformed/partial stdin, config parsing, determinism hook
pwsh tests/ps-tests.ps