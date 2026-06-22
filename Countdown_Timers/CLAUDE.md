# Countdown Timers - DMHub Mod

## What This Mod Does

Configurable countdown timers for DMHub. The GM creates named timers with a duration in minutes, then triggers them manually by clicking. Running timers display as overlay notifications (visible to all players) in the upper-right corner, counting down in real time. When a timer expires it shows "TIME'S UP" until the GM resets it.

## Architecture

Single file mod: `Main.lua`

### Components

- **Document System** (`timers:state`) - Stores all timer data: labels, durations, trigger type, and runtime end times. Synced across all clients.
- **DockablePanel** ("Countdown Timers", GM-only) - Sidebar panel showing a grid of timer cells. Each displays the duration (idle), live countdown (running), or "Done!" (expired). Click the visual to start/stop. Click the label to edit. Plus button to add new timers.
- **Countdown Overlay** - Attached to `dialogWorldPanel` (above map, below modals). Shows all running/expired timers as stacked notification cards in the upper-right corner. Visible to all players. Updates every second via `thinkTime`.
- **Edit Dialog** - Modal for GM to rename timers, change duration (1-120 minutes), or delete.

### Data Model

```lua
doc.data.timers[timerId] = {
    label = "Short Rest",       -- Display name
    durationMinutes = 10,       -- Configured duration
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
- **Closure pattern** for reliable element updates (avoids Styles.Panel/:Get() conflicts)

### Timer States

| State | Panel Display | Overlay | Colors |
|-------|--------------|---------|--------|
| Idle | Duration (e.g. "10m") | Hidden | Gray bg, gray border |
| Running | Countdown (e.g. "5:23") | Visible with countdown | Green bg, green border |
| Expired | "Done!" | Visible with "TIME'S UP" | Red bg, red border |

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
