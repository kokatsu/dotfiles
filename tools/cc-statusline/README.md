# cc-statusline

A fast statusline for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays model info, context usage, cost tracking, and burn rate. Written in Zig for minimal latency.

![screenshot](assets/screenshot.png)

## Features

- **Model & Context** — Current model name, context window usage with progress bar, lines added/removed
- **Cost Tracking** — Today's total cost, current block cost with remaining time, burn rate per hour
- **Smart Caching** — Binary cache with 30s TTL and incremental diff parsing for near-zero overhead
- **Pricing** — Supports Opus 4.6/4.5/4.1/4, Sonnet 4.6/4.5/4.2/4/3.7/3.5, Haiku 4.5/3.5 (including 200K+ tiered pricing)

## Requirements

- Zig 0.15.0+

## Build

```sh
zig build -Doptimize=ReleaseFast
```

The binary is output to `zig-out/bin/cc-statusline`.

## Usage

cc-statusline reads Claude Code's statusline JSON from stdin and outputs a 2-line ANSI-colored status:

```
🤖 Opus 4.6 | 🧠 ████████████░░░░░░░░ 60% | 📝 +3 -1
💰 $0.20 today | $0.20 block ██████████████░░░░░░ 4h 39m left 🔥 $0.60/h
```

### Claude Code Integration

Add to `~/.config/claude/settings.json`:

```json
{
  "statusline": {
    "command": "/path/to/cc-statusline"
  }
}
```

## Test

```sh
zig build test
```
