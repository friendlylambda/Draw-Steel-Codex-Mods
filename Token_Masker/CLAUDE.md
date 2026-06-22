# Token Masker - DMHub Mod

## What This Mod Does

A client-side token masking tool for DMHub. Players can configure a list of terms, and any tokens whose names match those terms will have their portrait replaced with a generic monster avatar. Useful for avoiding spoilers when a player recognizes a monster by its token art. Changes are local-only -- other players and the GM are unaffected.

## Architecture

Single file mod: `Main.lua`

### Components

- **Settings** - Two per-user preference settings: enable toggle (requires restart) and comma-separated mask terms
- **TokenHud Panel** (`tokenmasker:updater`) - Invisible 1x1 panel registered on every token via `TokenHud.RegisterPanel`. Runs periodic checks every 2s via `thinkTime` to apply/remove masks
- **Mask Logic** - Compares token names (case-insensitive) against parsed mask terms. Matching tokens get their portrait swapped to `DEFAULT_MONSTER_AVATAR`; originals are stored for restoration

### Key Patterns

- **`TokenHud.RegisterPanel`** - Attaches an invisible panel to each token for per-token periodic updates
- **Local-only modifications** - Uses `token:RefreshAppearanceLocally()` so changes only affect this client
- **Original state preservation** - `originalPortraits[tokenId]` stores original portrait and brightness for clean restoration when masking is disabled or terms change
- **`dmhub.InvalidateTokenUI()`** - Called at load time to force all tokens to pick up the new panel registration
- **Setting `storage = "preference"`** - All settings are per-user local preferences, not shared

### Notable API Usage

- `TokenHud.RegisterPanel{ id, ord, create }` - Register a panel on every token's HUD
- `token.name` / `token.charid` - Token identity
- `token.portrait` / `token.portraitFrameBrightness` - Token appearance
- `token:RefreshAppearanceLocally()` - Apply visual changes client-side only
- `dmhub.InvalidateTokenUI()` - Force rebuild of all token UI panels

## Reference Modules

The DMHub/Draw Steel core source lives in the codex repo at `~/draw-steel-codex` (read-only reference) -- use it as the API reference. See `~/draw-steel-codex/CLAUDE.md` for a directory guide, plus the API/design docs at the repo root (`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`, etc.).
