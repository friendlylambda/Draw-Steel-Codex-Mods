# DMHub Mod Development Reference

## Overview

This document captures learnings from developing DMHub mods, specifically focused on the Draw Steel game system. DMHub is a virtual tabletop application with a Lua-based modding API that is currently in alpha.

---

## Folder Structure

### Mod Organization
Each mod in this folder follows:
```
ModName_XXXX/           # A mod (XXXX = first 4 chars of UUID)
└── Main.lua            # Entry point, loaded automatically
```

### Reference source -- the codex repo
DMHub core module source is **not** in this folder. Read it in the codex repo at
`~/draw-steel-codex` (read-only reference; configured as an additional readable
directory). There is no official API documentation -- these modules are the
definitive reference for APIs and patterns. See `~/draw-steel-codex/CLAUDE.md` for
a directory guide, plus the API/design docs at the repo root
(`GoblinScript_Guide.md`, `UI_BEST_PRACTICES.md`, `DefaultStyles.md`,
`monster-reference.md`, etc.).

Key reference directories there:
- `Definitions/` - LuaLS type stubs for the engine API (`dmhub.lua`, `lua-core.lua`, etc.)
- `DMHub Core UI/` - core UI primitives (`gui.*`, `DockablePanel`, `Styles`)
- `DMHub Core Panels/` - dialogs, editors, settings panels
- `DMHub Game Hud/` - GameHud, overlay system, HUD layer hierarchy
- `DMHub Token UI/` - token HUD panels (`TokenHud.RegisterPanel`)
- `DMHub Game Rules/` - base game rules (abilities, creatures, conditions)
- `Draw Steel Core Rules/` - full Draw Steel system; excellent reference for action bars, character panels, abilities
- `Draw Steel UI/` - Draw Steel-specific UI components

---

## Core API Techniques

### GUI Elements

```lua
-- Basic elements
gui.Panel{ width = 100, height = 50, bgcolor = "#333" }
gui.Label{ text = "Hello", fontSize = 16, bold = true }
gui.Button{ text = "Click", click = function(element) ... end }

-- Common properties
width = 100           -- Fixed pixels
width = "100%"        -- Percentage of parent
width = "auto"        -- Size to content
height = "auto"
halign = "center"     -- "left", "center", "right"
valign = "center"     -- "top", "center", "bottom"
flow = "vertical"     -- "horizontal", "vertical"
vpad = 8, hpad = 8    -- Internal padding
vmargin = 8, hmargin = 8  -- External margin
```

### Registering Panels

```lua
-- Sidebar dockable panel
DockablePanel.Register{
    name = "My Panel",
    icon = "icons/icon_app/icon_app_73.png",
    dmonly = false,    -- false = visible to all users
    minHeight = 100,
    content = function()
        return gui.Panel{ ... }
    end,
}

-- Token HUD panel (attached to tokens)
TokenHud.RegisterPanel{
    id = "mymod:panel",
    ord = 100,         -- Sort order
    create = function(token, sharedInfo)
        return gui.Panel{ ... }  -- or nil for invisible bootstrap
    end,
}
```

### Cross-Client State Sync (Document System)

```lua
local BREAK_DOC_ID = "mymod:state"

local function GetDoc()
    return mod:GetDocumentSnapshot(BREAK_DOC_ID)
end

-- Reading
local doc = GetDoc()
local value = doc.data.someField

-- Writing (must wrap in change transaction)
local doc = GetDoc()
doc:BeginChange()
doc.data.someField = "new value"
doc:CompleteChange("Description of change")

-- Auto-refresh when document changes
gui.Panel{
    monitorGame = doc.path,
    events = {
        refreshGame = function(element)
            -- Called when document changes
        end,
    },
}
```

### Periodic Updates

```lua
gui.Panel{
    thinkTime = 1,  -- Seconds between think events
    events = {
        think = function(element)
            -- Called every thinkTime seconds
        end,
    },
}
```

### Element Lookup and Updates

```lua
-- Finding child elements by ID
local label = element:Get("myLabelId")
label.text = "Updated text"

-- Toggling visibility/styles via classes
element:SetClass("hidden", true)
element:SetClass("collapsed", true)
element:SetClass("myCustomClass", false)

-- Styles block for class-based styling
styles = {
    {
        selectors = {"hidden"},
        collapsed = 1,
    },
    {
        selectors = {"hover"},
        bgcolor = "#ffffff",
    },
},
```

---

## Critical Gotchas

### 0. No Unicode in Lua Files

DMHub's Lua parser does not handle unicode characters. **Never use non-ASCII characters** (em dashes, curly quotes, accented characters, etc.) in any Lua mod files. Use ASCII equivalents instead:
- `—` → `--`
- `'` `'` → `'`
- `"` `"` → `"`

### 1. Time Synchronization - USE SERVER TIME

**WRONG** - `dmhub.Time()` returns LOCAL app time (seconds since that client started):
```lua
-- Each client gets different values!
doc.data.endTime = dmhub.Time() + 60  -- BROKEN
```

**CORRECT** - `dmhub.serverTime` is synchronized across all clients:
```lua
doc.data.endTime = dmhub.serverTime + 60  -- Works correctly
```

### 2. GameHud Initialization Timing

The GameHud exists but isn't fully ready at module load time. **Use this pattern**:

```lua
dmhub.RegisterEventHandler("EnterGame", function()
    dmhub.Coroutine(function()
        -- Poll until HUD is fully ready
        while (not GameHud.instance) or
              (not GameHud.instance.dialogWorldPanel) or
              (not GameHud.instance.dialogWorldPanel.valid) do
            coroutine.yield()
        end

        -- Wait extra frames for safety
        for i = 1, 5 do
            coroutine.yield()
        end

        -- NOW safe to add overlays
        GameHud.instance.dialogWorldPanel:AddChild(myOverlay)
    end)
end)
```

### 3. HUD Panel Hierarchy (Z-Index)

```
Layer 1: documentsPanel (lowest)
Layer 2: dialogWorldPanel  <- For overlays above map
Layer 3: modalPanel        <- Character sheets, settings (gui.ShowModal)
Layer 4: popupPanel
Layer 5: connectionStatus (highest)
```

Use `dialogWorldPanel` for overlays that should appear above the map but below modal dialogs.

### 4. Closures vs :Get() for Updates

Both work, but closures are more reliable with complex style systems:

```lua
-- Closure pattern (more reliable)
local timerLabel = gui.Label{ text = "0:00" }
local panel = gui.Panel{
    events = {
        refresh = function(element)
            timerLabel.text = "1:30"  -- Direct reference
        end,
    },
    children = { timerLabel },
}

-- :Get() pattern (standard, but can break with Styles.Panel)
local panel = gui.Panel{
    events = {
        refresh = function(element)
            element:Get("timer").text = "1:30"
        end,
    },
    children = {
        gui.Label{ id = "timer", text = "0:00" },
    },
}
```

### 5. Parent Padding vs Child Margin

`hpad` on parent does NOT affect `width = "100%"` children:

```lua
-- WRONG - button still fills full width
gui.Panel{
    hpad = 16,
    children = {
        gui.Button{ width = "100%", text = "Click" },
    },
}

-- CORRECT - use margin on child, or auto width
gui.Button{ width = "auto", hmargin = 16, hpad = 16, text = "Click" }
```

### 6. Modal Dialog Styling

```lua
gui.Panel{
    classes = {"framedPanel"},
    styles = { Styles.Panel },
    -- This gives modal-like appearance with border/background
}
```

**Warning**: `Styles.Panel` can interfere with `:Get()` lookups. If updating elements in a framedPanel, prefer the closure pattern.

### 7. pcall Behavior

`pcall` catches Lua errors, but the engine may still log errors before Lua gets control:

```lua
local success = pcall(function()
    -- Error here is caught, but may still be logged by engine
end)
```

---

## Common Patterns

### Full-Screen Overlay

```lua
local function CreateOverlay()
    local contentLabel = gui.Label{ text = "Hello" }

    return gui.Panel{
        classes = {"hidden"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        floating = true,
        bgcolor = "#00000066",

        styles = {
            { selectors = {"hidden"}, collapsed = 1 },
        },

        events = {
            refresh = function(element)
                element:SetClass("hidden", not shouldShow)
                contentLabel.text = "Updated"  -- Closure reference
            end,
        },

        children = {
            gui.Panel{
                classes = {"framedPanel"},
                width = 400,
                height = "auto",
                -- Modal content here
                children = { contentLabel },
            },
        },
    }
end
```

### Button with Good Sizing

```lua
gui.Button{
    width = "auto",
    height = 40,
    halign = "center",
    hpad = 16,       -- Internal padding for text breathing room
    hmargin = 8,     -- External margin
    text = "Click Me",
    fontSize = 16,
    click = function(element) ... end,
}
```

### Hash-Based Change Detection (Prevent Flicker)

```lua
local lastHash = ""

local function buildHash()
    local parts = {}
    for _, item in ipairs(items) do
        parts[#parts+1] = item.id .. ":" .. item.status
    end
    return table.concat(parts, ",")
end

events = {
    refresh = function(element)
        local currentHash = buildHash()
        if currentHash ~= lastHash then
            lastHash = currentHash
            -- Only rebuild UI when data actually changed
            container.children = buildChildren()
        end
    end,
}
```

---

## Settings

```lua
setting{
    id = "mymod:enabled",
    description = "Enable Feature",
    editor = "check",      -- "check", "input", "dropdown"
    default = false,
    storage = "preference", -- "preference" = per-user, "game" = shared
    section = "General",
    help = "Help text shown to user",
}

-- Reading
local enabled = dmhub.GetSettingValue("mymod:enabled")
```

---

## Debugging Tips

1. **Check the console** for Lua errors - they show file:line and stack traces
2. **"Panel was created but not attached"** = orphaned panel, check AddChild timing
3. **Elements not updating** = try closure pattern instead of :Get()
4. **Timer desync between clients** = use `dmhub.serverTime` not `dmhub.Time()`
5. **Overlay not showing** = check HUD initialization timing, use EnterGame pattern

---

## API Notes (Alpha State)

The DMHub API is in active development. Behaviors may change. Key areas of instability:

1. **HUD initialization timing** - documented workaround above
2. **Style system interactions** - Styles.Panel can affect element lookups
3. **Event handler timing** - some events fire before UI is fully ready

When in doubt, check the reference source in `~/draw-steel-codex` (e.g. `DMHub Core UI/`, `DMHub Game Hud/`, `Draw Steel Core Rules/`) for working patterns.
