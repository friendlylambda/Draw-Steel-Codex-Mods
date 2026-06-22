# Safety Cards - DMHub Mod

## What This Mod Does

TTRPG safety tools for DMHub. Players can play red, yellow, or green safety cards via a sidebar panel or chat commands. Cards trigger full-screen notification overlays for the GM (and optionally all players). Supports anonymous card play and per-user visibility preferences.

## Architecture

Single file mod: `Main.lua`

### Components

- **DockablePanel** ("Safety Cards") - Three large colored buttons (red/yellow/green) for all users
- **Document System** (`safetycards:events`) - Stores the most recent card event per user with color, sender name, visibility preference, and timestamp
- **Notification Overlay** - Full-screen overlay on `dialogWorldPanel` showing stacked card notifications. Each card is a framed panel with color bar, card type label, optional sender name, and click-to-dismiss
- **Chat Command** - `Commands.safetycard` handler for `/safetycard red|yellow|green`
- **Settings** - Two per-user preference settings: anonymous mode (hides name) and show-to-all (makes cards visible to all players, not just GM)

### Key Patterns

- **GameHud EnterGame coroutine** for overlay attachment
- **Hash-based change detection** to only rebuild notification cards when events change
- **`loadTime` gating** - Cards played before the mod loaded are ignored (prevents stale notifications on rejoin)
- **Per-user dismissal tracking** - `dismissedEvents[userid] = timestamp` to track which cards have been dismissed locally
- **Recursive `rebuildCards()`** - Dismiss callback triggers immediate rebuild rather than waiting for next refresh cycle
- **`monitorGame`** on the document path for auto-refresh when any player plays a card

### Card Colors

| Color | Hex | Meaning |
|-------|-----|---------|
| Red | `#ff4444` | Stop -- immediate issue |
| Yellow | `#ffcc00` | Caution -- approaching a boundary |
| Green | `#44cc44` | All good -- positive signal |

## Reference Modules

The DMHub/Draw Steel core source lives in the codex repo at `~/draw-steel-codex` (read-only reference) -- use it as the API reference. See `~/draw-steel-codex/CLAUDE.md` for a directory guide, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
