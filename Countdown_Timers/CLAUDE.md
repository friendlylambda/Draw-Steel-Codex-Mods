# Countdown Timers - DMHub Mod

## What This Mod Does

Configurable countdown timers for DMHub. The GM creates named timers with a duration, then triggers them manually by clicking. Running timers display as overlay notifications (visible to all players) in the upper-right corner, counting down in real time. When a timer expires it shows "TIME'S UP" until the GM resets it.

## Architecture

Single file mod: `Main.lua`

### Components

- **Document System** (`timers:state`) - Stores all timer data: labels, durations, trigger type, and runtime end times. Synced across all clients.
- **DockablePanel** ("Countdown Timers", GM-only) - Sidebar panel showing a grid of timer cells. Each displays the duration (idle), live countdown (running), or "Done!" (expired). Click the visual to start/stop. Click the label to edit. Plus button to add new timers.
- **Countdown Overlay** - Attached to `dialogWorldPanel` (above map, below modals). Shows all running/expired timers as stacked notification cards in the upper-right corner. Visible to all players. Updates every second via `thinkTime`.
- **Edit Dialog** - Modal for GM to rename timers, change duration (30 seconds to 120 minutes, in 30-second steps), or delete.

### Data Model

```lua
doc.data.timers[timerId] = {
    label = "Short Rest",       -- Display name
    durationSeconds = 600,      -- Configured duration in seconds (30-7200, 30s steps; new timers default 60)
    triggerType = "manual",     -- Trigger condition (only "manual" for now)
    endTime = nil,              -- dmhub.serverTime when timer expires; nil = not running
}
doc.data.timerOrder = { "timer_1", "timer_2", ... }
doc.data.nextId = 2
```

### Key Patterns Used

- **Structure hash + closure updates** - The panel and overlay use a two-tier update strategy: a structure hash detects when timers are added/removed/started/stopped (triggering full rebuild), while running timer countdowns update via stored closure references to avoid rebuilding the GUI tree every second.
- **Grid layout** via manual row-batching (3 cells per row, same as Clocks)
- **`monitorGame`** on the document path for cross-client state sync
- **`thinkTime = 1`** on both panel and overlay for per-second countdown updates
- **`dmhub.serverTime`** for all timing (synchronized across clients)
- **GameHud EnterGame coroutine** for overlay attachment (same pattern as Safety Cards)
- **Closure pattern** for reliable element updates
- **Codex Theme Engine** - UI is fully themed via class names (no inline colors). The modal and the overlay each own a `ThemeEngine.GetStyles()` cascade root; the dockable content inherits the dock's cascade. The overlay re-resolves its styles after `AddChild`, on `OnThemeChanged`, and on each hidden->visible transition. Status colors via composition classes; note a composition class can recolor a `gui.Panel`/`gui.Label` but NOT a `gui.Button` (the `{label,button}` base rule out-specifies it), which is why the stop control is a panel.

### Timer States

Colors are theme-driven (Codex Theme Engine), not hardcoded -- they track the user's active color scheme. State maps to a semantic status token:

| State | Panel Display | Overlay | Status color |
|-------|--------------|---------|--------------|
| Idle | Duration (e.g. "10m") | Hidden | Neutral (`@border`) |
| Running | Countdown (e.g. "5:23") | Visible with countdown | Success / green (`borderSuccess` cell, `bgSuccess` bar) |
| Expired | "Done!" | Visible with "TIME'S UP" | Danger / red (`borderDanger` cell, `bgDanger` bar + `danger` text) |

### GM Interactions (Panel)

- **Click timer visual** - Start (if idle/expired) or stop (if running)
- **Click label** - Open edit dialog
- **Click +** - Create new timer

### Future: Trigger Conditions

The `triggerType` field currently only supports `"manual"`. Future trigger types could include:
- `"round_start"` - Auto-start when combat begins
- `"turn_start"` - Reset on each character's turn
- `"rest"` - Triggered by rest actions
- `"custom"` - Triggered by game events or chat commands

## Reference

The DMHub/Draw Steel core source lives in the codex repo at `~/draw-steel-codex` (read-only reference) -- use it as the API reference. See `~/draw-steel-codex/CLAUDE.md` for a directory guide, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
