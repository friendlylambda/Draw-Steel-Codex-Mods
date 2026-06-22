# Break Time - DMHub Mod

## What This Mod Does

Break Time is a DMHub mod for Draw Steel that provides a synchronized break timer for tabletop sessions. When the GM starts a break, all connected players see a full-screen overlay with a countdown timer and can mark themselves as "back" when ready.

## Architecture

Single file mod: `Main.lua`

### Components

- **Document** (`breaktime:state`) - Cross-client state for break active flag, end time, and per-player away/back status
- **GM Dockable Panel** - Sidebar panel to start/end breaks and monitor player readiness
- **Player Dockable Panel** - Read-only sidebar showing break status for non-GM users
- **Break Duration Dialog** - Modal for GM to set break length (1-60 min, +/- buttons)
- **Player Overlay** - Full-screen draggable/minimizable overlay shown to all users during a break

### Key Patterns

- **Closure pattern** for all UI updates (avoids `:Get()` issues with `Styles.Panel`)
- **Hash-based change detection** to prevent flicker when rebuilding player status lists
- **GameHud EnterGame coroutine** for safe overlay attachment
- **`dmhub.serverTime`** for cross-client synchronized countdown
- **`monitorGame` + `thinkTime`** combo for document-change and periodic timer updates

## Reference Modules

The codex repo at `~/draw-steel-codex` (configured as an additional read-only directory) contains the DMHub/Draw Steel core module source code. There is no official API documentation -- these modules are the definitive reference for available APIs and patterns.

See `~/draw-steel-codex/CLAUDE.md` for a directory guide and which modules to look at for what, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
