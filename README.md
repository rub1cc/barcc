# barcc

A native macOS menu bar app that tracks Claude Code usage and costs in real-time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## What it does

Parses Claude Code's JSONL logs from `~/.claude/projects` and displays:
- Real-time token consumption (input/output/cache)
- Estimated costs per model
- 30-day usage chart
- Daily breakdowns with model-specific stats

## Features

- **Color-coded cost indicator** — green/yellow/orange based on daily spend
- **Multi-model support** — Sonnet 3.5/4.5, Opus 4.5, Haiku 3.5
- **Auto-refresh** — Updates every 30 seconds
- **Screenshot export** — Save stats as PNG

## Installation

Download the latest `.dmg` from [Releases](../../releases), or build from source:

```bash
# Build release binary
swift build -c release

# Or use the build script for a full .app bundle
./scripts/build.sh bundle
```

## Build Scripts

```bash
./scripts/build.sh build     # Release binary only
./scripts/build.sh bundle    # Binary + .app bundle
./scripts/build.sh unsigned  # Bundle + DMG (no signing)
./scripts/build.sh all       # Full pipeline with signing & notarization
```

For signed/notarized builds, set these environment variables:
- `SIGNING_IDENTITY`
- `APPLE_ID`
- `TEAM_ID`
- `APP_PASSWORD`

## Project Structure

```
Sources/barcc/
├── main.swift           # Entry point
├── AppDelegate.swift    # Status bar + popover
├── MenuBarView.swift    # Main UI
├── StatsParser.swift    # Log parsing + cost calc
└── StatusBarIcon.swift  # Dynamic icon
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Claude Code installed with logs at `~/.claude/projects`

## License

MIT
