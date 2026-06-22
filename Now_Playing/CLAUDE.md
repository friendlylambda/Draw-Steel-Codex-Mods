# Now Playing - DMHub Mod

## What This Mod Does

An audio management sidebar panel for DMHub. Shows all currently playing sounds with per-track and master volume controls for the GM. Players see a filtered view showing only the solo'd track (if active). Includes a "solo mode" that automatically mutes all tracks except the most recently started one.

## Architecture

Single file mod: `Main.lua`

### Components

- **DockablePanel** ("Now Playing") - Sidebar panel for all users
- **Track Rows** - Per-track display with name, stop button (GM), and volume slider (GM)
- **Solo Mode** - GM toggle that auto-mutes all tracks except the latest; synced to players via document
- **Master Volume Controls** - Master volume slider, mute toggle, and stop-all button (GM only)
- **Document System** (`nowplaying:solo`) - Syncs the solo'd track ID to player clients so they see only the active track

### Key Patterns

- **`audio.currentlyPlaying`** - Engine table of currently playing sound events, iterated each refresh
- **`audio.events:Listen(panel)`** - Subscribes a panel to audio state change events
- **`thinkTime = 0.5`** with hash-based change detection for track list updates
- **Track order tracking** - Maintains an ordered list of asset IDs (newest last) for solo mode logic
- **Saved volumes** - Stores original volumes before solo-muting so they can be restored
- **DM vs player branching** - GM sees all tracks with controls; players see only the solo'd track (if any) via shared document
- **`cond()` helper** - Ternary-style function used throughout (e.g. `cond(audio.muted, 0, audio.masterVolume)`)

### Notable API Usage

- `audio.currentlyPlaying` - Table of active sound events keyed by asset ID
- `audio.StopSoundEvent(assetId)` / `audio.StopAllSoundEvents()` - Stop playback
- `audio.SetSoundEventVolume(assetId, volume)` / `audio.PreviewSoundEventVolume()` - Volume control
- `audio.masterVolume` / `audio.muted` / `audio.UploadMasterVolume()` / `audio.UploadMuted()` - Master audio controls
- `audio.numPlayingSounds` - Count of active sounds
- `assets.audioTable[assetId]` - Audio asset metadata (description, volume, loop)
- `gui.Slider` - Slider widget with preview/confirm events

## Reference Modules

The DMHub/Draw Steel core source lives in the codex repo at `~/draw-steel-codex` (read-only reference) -- use it as the API reference. See `~/draw-steel-codex/CLAUDE.md` for a directory guide, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
