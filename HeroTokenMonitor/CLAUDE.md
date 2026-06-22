# HeroTokenMonitor - DMHub Mod

## What This Mod Does

A GM-only background monitor for Draw Steel that sends chat reminders when hero tokens haven't been used for a configurable period. Encourages the table to use the hero token economy actively.

## Architecture

Single file mod: `Main.lua`

### Components

- **Settings** - Three GM-only game settings: enable/disable, wait time (minutes, min 5), and repeat toggle
- **Inactivity Checker** - Invisible 0x0 panel attached to `dialogWorldPanel` that runs periodic checks via `thinkTime`
- **Chat Alerts** - Sends reminder messages to chat via `chat.Send()` when inactivity threshold is exceeded

### How It Works

1. Every 30 seconds (`CHECK_INTERVAL`), the think handler fires
2. Checks: is GM? is enabled? are any players online?
3. Reads hero token history via `CharacterResource.GetGlobalResourceHistory(CharacterResource.heroTokenId)`
4. Parses the `when` string from the most recent history entry (e.g. "43 minutes ago", "an hour ago") to estimate minutes since last activity
5. If inactivity exceeds threshold, sends a chat reminder
6. Tracks alert state locally to avoid spamming (respects repeat setting)

### Key Patterns

- **GameHud EnterGame coroutine** for safe panel attachment (GM-only gate)
- **Invisible bootstrap panel** (0x0 size) -- exists only for its `thinkTime` handler
- **`dmhub.serverTime`** for tracking time between alerts
- **`dmhub.GetSessionInfo()` + `timeSinceLastContact`** for detecting online players
- **Setting `storage = "game"`** so all settings are shared/synced (GM configures once)

### Notable API Usage

- `CharacterResource.GetGlobalResourceHistory()` - Returns history table with `when` strings (not timestamps)
- `dmhub.IsUserDM(userid)` - Check if a user is the DM
- `chat.Send()` - Send a message to the game chat

## Reference Modules

The DMHub/Draw Steel core source lives in the codex repo at `~/draw-steel-codex` (read-only reference) -- use it as the API reference. See `~/draw-steel-codex/CLAUDE.md` for a directory guide, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
