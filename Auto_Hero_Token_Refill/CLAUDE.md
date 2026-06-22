# Auto Hero Token Refill - DMHub Mod

## What This Mod Does

A GM-only helper for Draw Steel that watches for the likely start of a play
session and offers to set the party's Hero Tokens to a configured amount (so the
Director never forgets the start-of-session refill). The GM can also apply a
refill manually at any time.

## Architecture

Single file mod: `Main.lua`

### Components

- **Document** (`autoherotokenrefill:state`) - One per-campaign document holding
  both the config (`data.config`) and runtime bookkeeping (`data.lastActionTime`).
  Storing config here makes settings persist per game/campaign and sync across
  the GM's devices.
- **GM Dockable Panel** ("Auto Hero Token Refill", `dmonly = true`) - Renders the
  settings as a live form (checkbox + `-/+` steppers), a status readout, and a
  "Set Hero Tokens Now" button. A "Reset detection" testing button is appended
  only when Codex Developer Mode is on (`devmode()`).
- **Detection Overlay** - An invisible, non-interactable full-screen panel on
  `dialogWorldPanel` (GM only) whose `thinkTime` re-evaluates the heuristic. When
  a session start is detected it un-hides a dismissible card ("Set Tokens" /
  "Not now"); declining just waits out the cooldown.

### Session-Start Heuristic (`ShouldTrigger`)

Prompts only when ALL hold (this combines the two signals the user wanted):

1. Detection enabled and Draw Steel rules loaded.
2. Not within the cooldown window since the last refill/dismissal
   (`lastActionTime`, synced via the document, so reloads don't re-prompt).
3. At least `playerThreshold` non-GM players are online (presence).
4. The hero token resource has NOT changed within the cooldown window
   (staleness -- a fresh session means tokens are "old"; brand-new campaigns with
   no history count as stale/eligible).

The cooldown (`COOLDOWN_HOURS`, fixed at 24h) doubles as the staleness threshold,
so a "new session" simply means "nothing token-related has happened for a day and
players are now here." This deliberately avoids wall-clock session-start times.

### Settings (per-campaign, in `data.config`)

Deliberately minimal -- only three knobs; everything else is a sensible constant.

- `enabled` - master switch for detection (default **off**; opt-in)
- `fixedAmount` - the "Number of Hero Tokens" to set (default 2)
- `playerThreshold` - players online required to consider a session live (default 2)

Fixed behavior (not exposed): cooldown/staleness window is 24h, refills always
**set** to the configured number (decline the prompt to skip), and the prompt
always asks first (no hands-free mode).

### Hero Token API (Draw Steel)

- Read:  `CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)`
- Write: `CharacterResource.SetGlobalResource(heroTokenId, amount, note)` -- wraps
  its own change transaction and clamps to >= 0; do NOT wrap it.
- History: `CharacterResource.GetGlobalResourceHistory(heroTokenId)` -- entries
  carry a human `when` string ("43 minutes ago"); we parse that for staleness
  (hour granularity is enough for a multi-hour cooldown).

### Key Patterns

- **GameHud EnterGame coroutine** for safe overlay attachment (GM-only gate).
- **Closure pattern** for all UI updates (no `:Get()` under `Styles.Panel`).
- **`dmhub.serverTime`** for the synced cooldown timestamp.
- **Forward-declared `card`/`hideCard`** so button `click` handlers stay inline.
- **Non-interactable overlay container** so the empty screen never eats map clicks;
  only the prompt card sets `interactable = true`.

## Deployment

Copy this folder into the Codex mods directory
(`~/Library/Application Support/com.MCDM.Codex/mods/`). The `modid` in
`status.json` is a placeholder; if Codex assigns a different id when you create
the mod in-app, use its value.

## Reference

The codex repo at `~/draw-steel-codex` contains the DMHub/Draw Steel core source. See
`~/draw-steel-codex/CLAUDE.md` for a directory guide. `../HeroTokenMonitor/Main.lua` is a close sibling
(presence detection + hero token history parsing).
