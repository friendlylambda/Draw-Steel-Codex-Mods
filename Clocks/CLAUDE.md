# Clocks - DMHub Mod

## What This Mod Does

Progress clocks for DMHub, inspired by Blades in the Dark / Draw Steel mechanics. The GM creates named clocks with configurable slice counts (1-16), fills/unfills them via click interactions, and toggles per-clock visibility to players. All state is synced across clients via the document system.

## Architecture

Single file mod: `Main.lua`

### Components

- **Document System** (`clocks:state`) - Stores all clock data: labels, slice counts, fill state, visibility, and display order
- **DockablePanel** ("Clocks") - Sidebar panel visible to all users; GM sees all clocks with edit/visibility controls, players only see clocks marked visible
- **Edit Dialog** - Modal for GM to rename clocks, change slice count, or delete
- **Clock Visual** (`CreateClockVisual`) - Renders a pre-rendered clock face image looked up by name, with a `filled/total` text fallback if the image is missing

### Key Patterns Used

- **Hash-based change detection** (`buildHash`) to avoid rebuilding UI on every refresh
- **Grid layout** via manual row-batching (3 cells per row)
- **`monitorGame`** on the document path for automatic refresh on state change
- **DM vs player branching** - GM gets click handlers, eye toggle, add/edit; players get read-only view
- **Image assets** via `mod.images["clock-N-M"]` sprite lookup

### Assets

- Clock faces are PNGs imported into the mod's DMHub assets, named `clock-{total}-{filled}` (e.g., `clock-4-2` for a 4-slice clock with 2 filled). Covers totals 1-16.
- `clockgen.zip` holds the generator (`generate-clocks.ts`, a node-canvas script) that renders those PNGs -- it is gitignored. Unzip it to `clockgen/`, run `npm ci && npm run generate`, and the faces land in `clockgen/clocks/`. New/changed images must be imported into DMHub manually; re-zip `clockgen/` back over `clockgen.zip` after editing the script.

## Reference

The DMHub/Draw Steel core source lives in the codex repo at `~/draw-steel-codex` (read-only reference) -- use it as the API reference. See `~/draw-steel-codex/CLAUDE.md` for a directory guide, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
