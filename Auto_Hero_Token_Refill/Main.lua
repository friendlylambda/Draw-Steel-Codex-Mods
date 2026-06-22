-- Auto Hero Token Refill
-- A GM-only helper for Draw Steel that detects when a play session has likely
-- started and offers to set the party's Hero Tokens to a configured amount.
--
-- Session-start heuristic (see ShouldTrigger): we prompt only when BOTH
--   (1) enough players are online (presence), AND
--   (2) the hero token resource has not changed in at least the cooldown
--       window (staleness -- a fresh session means tokens are "old"),
-- and we have not already acted within that same cooldown window (a synced
-- timestamp prevents double-prompting across reloads / the GM's other devices).
--
-- All config + bookkeeping lives in one per-campaign document, so settings are
-- stored per game/campaign and the GM panel edits them live.

local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
-- CONSTANTS / DEFAULTS
--------------------------------------------------------------------------------

local DOC_ID = "autoherotokenrefill:state"

-- How often (seconds) the background checker re-evaluates the heuristic.
local CHECK_INTERVAL = 15

-- Hours of "quiet" (no hero-token change, refill, or dismissal) before a fresh
-- session is assumed. Fixed at one day so a weekly game prompts once per session.
local COOLDOWN_HOURS = 24

-- Default configuration. The GM can change these from the panel; the document
-- overrides them per campaign.
local DEFAULTS = {
    enabled         = false,  -- master switch (opt-in -- off until the GM enables)
    fixedAmount     = 2,      -- "Number of Hero Tokens" to set
    playerThreshold = 2,      -- players online before we consider a session live
}

local MIN_AMOUNT, MAX_AMOUNT = 0, 20
local MIN_PLAYERS, MAX_PLAYERS = 1, 10

--------------------------------------------------------------------------------
-- DOCUMENT ACCESS / CONFIG
--------------------------------------------------------------------------------

local function GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

-- Read the merged config (defaults overlaid with whatever is stored).
local function GetConfig()
    local cfg = {}
    for k, v in pairs(DEFAULTS) do
        cfg[k] = v
    end

    local doc = GetDoc()
    if doc.data ~= nil and doc.data.config ~= nil then
        for k, v in pairs(doc.data.config) do
            if cfg[k] ~= nil then
                cfg[k] = v
            end
        end
    end

    cfg.cooldownSeconds = COOLDOWN_HOURS * 3600
    return cfg
end

local function SetConfigField(key, value)
    local doc = GetDoc()
    doc:BeginChange()
    doc.data = doc.data or {}
    doc.data.config = doc.data.config or {}
    doc.data.config[key] = value
    doc:CompleteChange("Update Auto Hero Token Refill setting")
end

-- Stamp the synced "we acted" time. Used both after a refill and after a
-- dismissal so the prompt does not return until the next session.
local function RecordAction()
    local doc = GetDoc()
    doc:BeginChange()
    doc.data = doc.data or {}
    doc.data.lastActionTime = dmhub.serverTime
    doc:CompleteChange("Auto Hero Token Refill action")
end

local function GetLastActionTime()
    local doc = GetDoc()
    if doc.data ~= nil and doc.data.lastActionTime ~= nil then
        return doc.data.lastActionTime
    end
    return 0
end

--------------------------------------------------------------------------------
-- HERO TOKEN ACCESS (Draw Steel)
--------------------------------------------------------------------------------

-- Returns false if the Draw Steel core rules (which define the hero token
-- resource) are not loaded, so the mod degrades gracefully.
local function HeroTokensAvailable()
    return CharacterResource ~= nil and CharacterResource.heroTokenId ~= nil
end

local function GetHeroTokens()
    if not HeroTokensAvailable() then
        return 0
    end
    return CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) or 0
end

local function SetHeroTokens(amount, note)
    if not HeroTokensAvailable() then
        return
    end
    -- SetGlobalResource wraps its own BeginChange/CompleteChange and clamps >= 0.
    CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, amount, note)
end

--------------------------------------------------------------------------------
-- HERO TOKEN STALENESS (port of the proven HeroTokenMonitor parser)
--------------------------------------------------------------------------------

-- The history "when" field is a human string ("43 minutes ago", "an hour ago").
-- Hour granularity is plenty for a multi-hour cooldown.
local function ParseWhenString(when)
    if when:find("day") then
        local num = tonumber(when:match("(%d+)")) or 1
        return num * 60 * 24
    end
    if when:find("hour") then
        local num = tonumber(when:match("(%d+)")) or 1
        return num * 60
    end
    if when:find("minute") then
        local num = tonumber(when:match("(%d+)"))
        if num then
            return num
        end
    end
    -- "just now" or unparseable -> treat as very recent
    return 0
end

-- Minutes since the most recent hero token change, or nil if there is no
-- history at all (a brand new campaign -- treated as "stale / eligible").
local function GetMinutesSinceLastTokenChange()
    if not HeroTokensAvailable() then
        return nil
    end

    local history = CharacterResource.GetGlobalResourceHistory(CharacterResource.heroTokenId)
    local lastKey = nil
    for k, _ in pairs(history) do
        if lastKey == nil or k > lastKey then
            lastKey = k
        end
    end

    if lastKey == nil then
        return nil
    end

    return ParseWhenString(history[lastKey].when or "")
end

--------------------------------------------------------------------------------
-- PRESENCE
--------------------------------------------------------------------------------

local function CountOnlinePlayers()
    local count = 0
    for _, userid in ipairs(dmhub.users) do
        if not dmhub.IsUserDM(userid) then
            local sessionInfo = dmhub.GetSessionInfo(userid)
            if sessionInfo and not sessionInfo.loggedOut and sessionInfo.timeSinceLastContact < 35 then
                count = count + 1
            end
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- HEURISTIC + REFILL
--------------------------------------------------------------------------------

-- The combined session-start gate. Returns (shouldTrigger, reasonString).
local function ShouldTrigger(cfg)
    if not cfg.enabled then
        return false, "Detection disabled"
    end
    if not HeroTokensAvailable() then
        return false, "Draw Steel rules not loaded"
    end

    if (dmhub.serverTime - GetLastActionTime()) < cfg.cooldownSeconds then
        return false, "Recently refilled / dismissed"
    end

    if CountOnlinePlayers() < cfg.playerThreshold then
        return false, "Waiting for players"
    end

    local mins = GetMinutesSinceLastTokenChange()
    if mins ~= nil and (mins * 60) < cfg.cooldownSeconds then
        return false, "Tokens changed recently"
    end

    return true, "Session start detected"
end

-- Apply a refill now and stamp the action time.
local function ApplyRefill(amount, note)
    SetHeroTokens(amount, note or "Auto Hero Token Refill (session start)")
    RecordAction()
end

--------------------------------------------------------------------------------
-- PROMPT OVERLAY (GM only, dismissible card above the map)
--------------------------------------------------------------------------------

-- Local (per client) flag so we do not re-show while a card is already up.
local promptVisible = false

local function CreatePromptOverlay()
    -- Forward-declared so the inline button click handlers below can close over
    -- them; they are assigned before any click can fire at runtime.
    local pendingAmount = 0
    local card
    local hideCard

    local messageLabel = gui.Label{
        text = "",
        fontSize = 15,
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 10,
    }

    local setButton = gui.Button{
        text = "Set Tokens",
        width = 130,
        height = 36,
        hmargin = 6,
        fontSize = 15,
        click = function()
            ApplyRefill(pendingAmount)
            hideCard()
        end,
    }

    local dismissButton = gui.Button{
        text = "Not now",
        width = 110,
        height = 36,
        hmargin = 6,
        fontSize = 15,
        click = function()
            -- Treat "Not now" as an action so we wait a full cooldown before
            -- asking again (no nagging mid-session). The GM can still use the
            -- panel's "Set Hero Tokens Now" button at any time.
            RecordAction()
            hideCard()
        end,
    }

    card = gui.Panel{
        classes = { "framedPanel", "hidden" },
        styles = {
            Styles.Panel,
            { selectors = { "hidden" }, collapsed = 1 },
        },
        width = 360,
        height = "auto",
        halign = "center",
        valign = "top",
        vmargin = 120,
        flow = "vertical",
        vpad = 16,
        hpad = 16,
        interactable = true,

        gui.Label{
            text = "Session Started?",
            fontSize = 20,
            bold = true,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 6,
        },

        messageLabel,

        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            vmargin = 6,
            interactable = true,
            children = { setButton, dismissButton },
        },
    }

    hideCard = function()
        promptVisible = false
        card:SetClass("hidden", true)
    end

    local function showCard(amount)
        pendingAmount = amount
        messageLabel.text = "It looks like your session just started. Set Hero Tokens to " ..
            tostring(amount) .. "?"
        promptVisible = true
        card:SetClass("hidden", false)
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "top",
        floating = true,
        -- Container stays non-interactable so empty screen area never eats map
        -- clicks; the card below opts back in with interactable = true.
        interactable = false,
        thinkTime = CHECK_INTERVAL,

        events = {
            think = function(element)
                if not dmhub.isDM or promptVisible then
                    return
                end
                local cfg = GetConfig()
                if not ShouldTrigger(cfg) then
                    return
                end

                showCard(cfg.fixedAmount)
            end,
        },

        children = { card },
    }
end

--------------------------------------------------------------------------------
-- GM SETTINGS PANEL
--------------------------------------------------------------------------------

local function ConfigCheck(label, key)
    return gui.Check{
        text = label,
        value = GetConfig()[key],
        halign = "left",
        width = "auto",
        minWidth = 0,
        vmargin = 3,
        change = function(element)
            SetConfigField(key, element.value)
        end,
    }
end

-- A labeled "-  value  +" stepper bound to a config field.
local function ConfigStepper(label, key, minVal, maxVal)
    local valueLabel = gui.Label{
        text = tostring(GetConfig()[key]),
        fontSize = 16,
        width = 46,
        height = 30,
        halign = "center",
        valign = "center",
        textAlignment = "center",
        bgcolor = "#333333",
        borderWidth = 1,
        borderColor = "#666666",
    }

    local function apply(delta)
        local v = math.max(minVal, math.min(maxVal, GetConfig()[key] + delta))
        SetConfigField(key, v)
        valueLabel.text = tostring(v)
    end

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        halign = "left",
        vmargin = 3,

        children = {
            gui.Label{
                text = label,
                fontSize = 14,
                width = 170,
                height = "auto",
                valign = "center",
                halign = "left",
            },
            gui.Button{
                text = "-",
                width = 30, height = 30, fontSize = 20, hmargin = 4,
                click = function() apply(-1) end,
            },
            valueLabel,
            gui.Button{
                text = "+",
                width = 30, height = 30, fontSize = 20, hmargin = 4,
                click = function() apply(1) end,
            },
        },
    }
end

local function CreateSettingsPanel()
    local doc = GetDoc()

    local statusLabel = gui.Label{
        text = "",
        fontSize = 13,
        color = "#cccccc",
        width = "100%",
        height = "auto",
        vmargin = 4,
    }

    local function refreshStatus()
        local cfg = GetConfig()
        local _, reason = ShouldTrigger(cfg)
        local mins = GetMinutesSinceLastTokenChange()
        local lastChange
        if mins == nil then
            lastChange = "never"
        elseif mins < 60 then
            lastChange = mins .. "m ago"
        else
            lastChange = string.format("%.1fh ago", mins / 60)
        end
        statusLabel.text = string.format(
            "Hero Tokens: %d   Players online: %d\nLast token change: %s\nStatus: %s",
            GetHeroTokens(), CountOnlinePlayers(), lastChange, reason)
    end

    refreshStatus()

    local children = {
        gui.Label{
            text = "Auto Hero Token Refill",
            fontSize = 18,
            bold = true,
            width = "100%",
            height = "auto",
            vmargin = 4,
        },

        ConfigCheck("Enable session-start detection", "enabled"),
        ConfigStepper("Number of Hero Tokens", "fixedAmount", MIN_AMOUNT, MAX_AMOUNT),
        ConfigStepper("Players online to trigger", "playerThreshold", MIN_PLAYERS, MAX_PLAYERS),

        statusLabel,

        gui.Button{
            text = "Set Hero Tokens Now",
            width = "auto",
            height = 36,
            hpad = 16,
            halign = "center",
            vmargin = 8,
            fontSize = 14,
            click = function()
                ApplyRefill(GetConfig().fixedAmount, "Auto Hero Token Refill (manual)")
                refreshStatus()
            end,
        },
    }

    -- Testing aid: clears the cooldown so the prompt can fire again. Only shown
    -- when Codex Developer Mode is enabled.
    if devmode() then
        children[#children + 1] = gui.Button{
            text = "Reset detection (allow re-prompt)",
            width = "auto",
            height = 30,
            hpad = 12,
            halign = "center",
            fontSize = 12,
            click = function()
                local d = GetDoc()
                d:BeginChange()
                d.data = d.data or {}
                d.data.lastActionTime = 0
                d:CompleteChange("Reset Auto Hero Token Refill detection")
                refreshStatus()
            end,
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 8,
        hpad = 8,
        monitorGame = doc.path,
        thinkTime = 2,

        events = {
            refreshGame = function() refreshStatus() end,
            think = function() refreshStatus() end,
        },

        children = children,
    }
end

--------------------------------------------------------------------------------
-- REGISTRATION / INITIALIZATION
--------------------------------------------------------------------------------

DockablePanel.Register{
    name = "Auto Hero Token Refill",
    icon = mod.images["panel-icon"],
    dmonly = true,
    minHeight = 150,
    vscroll = true,
    content = function()
        return CreateSettingsPanel()
    end,
}

-- Attach the GM-only detection overlay once the HUD is ready.
local overlayAdded = false

dmhub.RegisterEventHandler("EnterGame", function()
    if not dmhub.isDM then
        return
    end

    dmhub.Coroutine(function()
        while (not GameHud.instance) or
              (not GameHud.instance.dialogWorldPanel) or
              (not GameHud.instance.dialogWorldPanel.valid) do
            coroutine.yield()
        end

        for i = 1, 5 do
            coroutine.yield()
        end

        if not overlayAdded then
            GameHud.instance.dialogWorldPanel:AddChild(CreatePromptOverlay())
            overlayAdded = true
        end
    end)
end)
