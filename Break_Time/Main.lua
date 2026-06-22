local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local BREAK_DOC_ID = "breaktime:state"

--------------------------------------------------------------------------------
-- THEME COLORS
--------------------------------------------------------------------------------
-- Pull semantic colors from DMHub's global Styles palette (the active theme)
-- instead of hardcoding hex values, and apply them inline on each element so
-- they render correctly everywhere -- including the modal dialog and the
-- full-screen overlay, which live outside any themed container and so do not
-- pick up registered panel themes. Resolved lazily so the Styles global is
-- guaranteed loaded by the time the UI is built. Re-theme by editing this table.

local _theme = nil
local function Theme()
    if _theme == nil then
        -- Bound ONLY to DMHub's semantic color tokens (no palette swatches like
        -- Gold/Grey/Cream, which are fixed and do not track the active theme).
        -- Re-theme by editing this table.
        _theme = {
            surface = Styles.backgroundColor,   -- neutral panel background
            text    = Styles.textColor,         -- primary text / neutral state
            active  = Styles.ModifierBuffColor, -- "back"/ready + "Break is Over!"
        }
    end
    return _theme
end

--------------------------------------------------------------------------------
-- DOCUMENT ACCESS
--------------------------------------------------------------------------------

local function GetBreakDoc()
    return mod:GetDocumentSnapshot(BREAK_DOC_ID)
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Get remaining seconds in the break
local function GetRemainingSeconds()
    local doc = GetBreakDoc()
    if doc.data == nil or not doc.data.active then
        return 0
    end
    return math.max(0, doc.data.endTime - dmhub.serverTime)
end

-- Format seconds as "M:SS"
local function FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

-- Check if break is currently active
local function IsBreakActive()
    local doc = GetBreakDoc()
    return doc.data ~= nil and doc.data.active == true
end

-- Start a break for the specified number of minutes
local function StartBreak(minutes)
    local doc = GetBreakDoc()
    doc:BeginChange()

    -- Initialize data if needed
    doc.data = doc.data or {}
    doc.data.active = true
    doc.data.endTime = dmhub.serverTime + (minutes * 60)
    doc.data.playerStatus = {}

    -- Set all current users to "away"
    for _, userid in ipairs(dmhub.users) do
        doc.data.playerStatus[userid] = "away"
    end

    doc:CompleteChange("Start break")
end

-- End the current break
local function EndBreak()
    local doc = GetBreakDoc()
    doc:BeginChange()
    doc.data.active = false
    doc.data.playerStatus = {}
    doc:CompleteChange("End break")
end

-- Toggle the current user's away/back status
local function ToggleMyStatus()
    local doc = GetBreakDoc()
    if doc.data == nil or not doc.data.active then
        return
    end

    doc:BeginChange()
    doc.data.playerStatus = doc.data.playerStatus or {}
    local current = doc.data.playerStatus[dmhub.userid] or "away"
    doc.data.playerStatus[dmhub.userid] = (current == "away") and "back" or "away"
    doc:CompleteChange("Toggle break status")
end

-- Get a user's current status ("away" or "back")
local function GetUserStatus(userid)
    local doc = GetBreakDoc()
    if doc.data == nil or doc.data.playerStatus == nil then
        return "away"
    end
    return doc.data.playerStatus[userid] or "away"
end

--------------------------------------------------------------------------------
-- BREAK START DIALOG
--------------------------------------------------------------------------------

local function ShowBreakDurationDialog()
    local minutesInput = 5  -- Default 5 minutes

    local inputLabel = gui.Label{
        classes = {"framedPanel"},
        styles = { Styles.Panel },
        text = "5",
        fontSize = 24,
        color = Theme().text,
        width = 60,
        height = 40,
        halign = "center",
        valign = "center",
        textAlignment = "center",
    }

    local decreaseButton = gui.Button{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        text = "-",
        fontSize = 24,

        click = function(element)
            minutesInput = math.max(1, minutesInput - 1)
            inputLabel.text = tostring(minutesInput)
        end,
    }

    local increaseButton = gui.Button{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        text = "+",
        fontSize = 24,

        click = function(element)
            minutesInput = math.min(60, minutesInput + 1)
            inputLabel.text = tostring(minutesInput)
        end,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        width = 300,
        height = 200,
        halign = "center",
        valign = "center",
        flow = "vertical",
        vpad = 16,
        hpad = 16,

        styles = {
            Styles.Panel,
        },

        -- Title
        gui.Label{
            text = "Start Break",
            fontSize = 20,
            bold = true,
            color = Theme().text,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 8,
        },

        -- Minutes label
        gui.Label{
            text = "Duration (minutes):",
            fontSize = 14,
            color = Theme().text,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 8,
        },

        -- Input row
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            vmargin = 8,

            children = {
                decreaseButton,
                inputLabel,
                increaseButton,
            },
        },

        -- Button row
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            vmargin = 16,

            -- Cancel button
            gui.Button{
                width = 100,
                height = 36,
                hmargin = 8,
                text = "Cancel",
                fontSize = 14,

                click = function(element)
                    gui.CloseModal()
                end,
            },

            -- Start button
            gui.Button{
                width = 100,
                height = 36,
                hmargin = 8,
                text = "Start",
                fontSize = 14,

                click = function(element)
                    StartBreak(minutesInput)
                    gui.CloseModal()
                end,
            },
        },

        -- Close button (X)
        gui.CloseButton{
            halign = "right",
            valign = "top",
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                gui.CloseModal()
            end,
        },
    }

    gui.ShowModal(dialogPanel)
end

--------------------------------------------------------------------------------
-- GM DOCKABLE PANEL
--------------------------------------------------------------------------------

local function CreatePlayerStatusRow(userid)
    local sessionInfo = dmhub.GetSessionInfo(userid)
    if sessionInfo == nil then
        return nil
    end

    local displayName = sessionInfo.displayName or "Unknown"
    local status = GetUserStatus(userid)
    local isBack = (status == "back")

    return gui.Panel{
        width = "100%",
        height = 24,
        flow = "horizontal",
        vmargin = 2,

        data = {
            userid = userid,
        },

        children = {
            -- Status indicator dot (active = ready, neutral = away)
            gui.Panel{
                bgcolor = isBack and Theme().active or Theme().text,
                width = 12,
                height = 12,
                cornerRadius = 6,
                valign = "center",
                hmargin = 4,
            },
            -- Name label
            gui.Label{
                text = displayName,
                fontSize = 14,
                color = Theme().text,
                width = 120,
                height = "auto",
                valign = "center",
            },
            -- Status text label (active when back, neutral when away)
            gui.Label{
                text = isBack and "Back" or "Away",
                fontSize = 12,
                color = isBack and Theme().active or Theme().text,
                width = "auto",
                height = "auto",
                valign = "center",
            },
        },
    }
end

local function CreateBreakPanel()
    local doc = GetBreakDoc()
    local lastUserHash = ""
    local lastStatusHash = ""

    -- Timer display (large, centered)
    local timerLabel = gui.Label{
        id = "gmTimerLabel",
        text = "0:00",
        color = Theme().text,
        fontSize = 32,
        bold = true,
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 8,
    }

    -- Player status list container
    local playerListContainer = gui.Panel{
        id = "playerListContainer",
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 8,
    }

    -- Start Break button
    local startButton = gui.Button{
        id = "startButton",
        width = "auto",
        height = 40,
        halign = "center",
        vmargin = 8,
        hmargin = 8,
        hpad = 16,
        text = "Start Break",
        fontSize = 16,

        click = function(element)
            ShowBreakDurationDialog()
        end,
    }

    -- End Break button
    local endButton = gui.Button{
        id = "endButton",
        width = "auto",
        height = 40,
        halign = "center",
        vmargin = 8,
        hmargin = 8,
        hpad = 16,
        text = "End Break",
        fontSize = 16,

        click = function(element)
            EndBreak()
        end,
    }

    -- Helper to build hash of users and their statuses
    local function buildStatusHash()
        local parts = {}
        for _, userid in ipairs(dmhub.users) do
            local status = GetUserStatus(userid)
            parts[#parts + 1] = userid .. ":" .. status
        end
        return table.concat(parts, ",")
    end

    -- Main panel
    local mainPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        vpad = 8,
        hpad = 16,

        monitorGame = doc.path,
        thinkTime = 1,

        events = {
            refreshGame = function(element)
                local active = IsBreakActive()

                -- Toggle visibility of elements
                timerLabel:SetClass("collapsed", not active)
                playerListContainer:SetClass("collapsed", not active)
                endButton:SetClass("collapsed", not active)
                startButton:SetClass("collapsed", active)

                if active then
                    -- Update timer text
                    local remaining = GetRemainingSeconds()
                    if remaining > 0 then
                        timerLabel.text = FormatTime(remaining)
                    else
                        timerLabel.text = "Break Over!"
                    end

                    -- Only rebuild player list if users or statuses changed
                    local currentHash = buildStatusHash()
                    if currentHash ~= lastStatusHash then
                        lastStatusHash = currentHash
                        local children = {}
                        for _, userid in ipairs(dmhub.users) do
                            local row = CreatePlayerStatusRow(userid)
                            if row then
                                children[#children + 1] = row
                            end
                        end
                        playerListContainer.children = children
                    end
                end
            end,

            think = function(element)
                element:FireEvent("refreshGame")
            end,
        },

        children = {
            timerLabel,
            playerListContainer,
            startButton,
            endButton,
        },
    }

    -- Initial state
    mainPanel:FireEvent("refreshGame")

    return mainPanel
end

-- Player-only panel (just shows status list, no controls)
local function CreatePlayerBreakPanel()
    local doc = GetBreakDoc()
    local lastStatusHash = ""

    -- Player status list container
    local playerListContainer = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 8,
    }

    -- "No break active" message
    local noBreakLabel = gui.Label{
        text = "No break active",
        color = Theme().text,
        fontSize = 14,
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 8,
    }

    -- Helper to build hash of users and their statuses
    local function buildStatusHash()
        local parts = {}
        for _, userid in ipairs(dmhub.users) do
            local status = GetUserStatus(userid)
            parts[#parts + 1] = userid .. ":" .. status
        end
        return table.concat(parts, ",")
    end

    local mainPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        vpad = 8,
        hpad = 8,

        monitorGame = doc.path,
        thinkTime = 1,

        events = {
            refreshGame = function(element)
                local active = IsBreakActive()

                noBreakLabel:SetClass("collapsed", active)
                playerListContainer:SetClass("collapsed", not active)

                if active then
                    -- Only rebuild player list if users or statuses changed
                    local currentHash = buildStatusHash()
                    if currentHash ~= lastStatusHash then
                        lastStatusHash = currentHash
                        local children = {}
                        for _, userid in ipairs(dmhub.users) do
                            local row = CreatePlayerStatusRow(userid)
                            if row then
                                children[#children + 1] = row
                            end
                        end
                        playerListContainer.children = children
                    end
                end
            end,

            think = function(element)
                element:FireEvent("refreshGame")
            end,
        },

        children = {
            noBreakLabel,
            playerListContainer,
        },
    }

    mainPanel:FireEvent("refreshGame")
    return mainPanel
end

--------------------------------------------------------------------------------
-- PLAYER OVERLAY (Visible to all users during break)
--------------------------------------------------------------------------------

local function CreateBreakOverlay()
    local doc = GetBreakDoc()
    local lastBreakEndTime = nil  -- Track which break we're on to reset position
    local isMinimized = false

    -- Create elements as locals for closure access
    local timerLabel = gui.Label{
        text = "0:00",
        color = Theme().text,
        fontSize = 72,
        bold = true,
        width = 200,
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 16,
    }

    local breakOverLabel = gui.Label{
        classes = {"collapsed"},
        text = "Break is Over!",
        color = Theme().active,
        fontSize = 28,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 16,
    }

    local toggleButton = gui.Button{
        width = 200,
        height = 50,
        halign = "center",
        vmargin = 16,
        text = "I'm Back",
        fontSize = 18,

        click = function(element)
            ToggleMyStatus()
        end,
    }

    local minimizeButton = gui.Button{
        width = 28,
        height = 28,
        text = "-",
        fontSize = 14,
        bold = true,
        vmargin = -2,

        click = function(element)
            isMinimized = not isMinimized
            element.text = isMinimized and "+" or "-"
            timerLabel:SetClass("collapsed", isMinimized)
            toggleButton:SetClass("collapsed", isMinimized)
            -- Let refreshGame handle breakOverLabel visibility based on time remaining
            if isMinimized then
                breakOverLabel:SetClass("collapsed", true)
            end
        end,
    }

    local contentPanel = gui.Panel{
        classes = {"framedPanel"},
        width = 400,
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",
        vpad = 24,
        hpad = 24,

        -- Enable dragging
        draggable = true,
        constrainToScreen = true,
        x = 0,
        y = 0,

        styles = {
            Styles.Panel,
        },

        events = {
            drag = function(element)
                element.x = element.xdrag
                element.y = element.ydrag
            end,
        },

        children = {
            -- Header row with minimize button and title
            gui.Panel{
                width = 352,
                height = 28,
                flow = "horizontal",
                vmargin = 8,

                children = {
                    minimizeButton,
                    -- Center title (352 - 28 button = 324)
                    gui.Label{
                        text = "Break Time",
                        fontSize = 20,
                        bold = true,
                        color = Theme().text,
                        width = 324,
                        height = 28,
                        halign = "center",
                        valign = "center",
                        textAlignment = "Center",
                    },
                },
            },
            timerLabel,
            breakOverLabel,
            toggleButton,
        },
    }

    -- Main overlay panel (full screen)
    local overlayPanel = gui.Panel{
        classes = {"breakOverlay", "hidden"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        floating = true,
        interactable = true,
        -- Semi-transparent black scrim dimming the map; this is an intentional
        -- backdrop, not a theme color, so it stays a fixed translucent black.
        bgcolor = "#00000066",

        monitorGame = doc.path,
        thinkTime = 1,

        styles = {
            {
                selectors = {"hidden"},
                collapsed = 1,
            },
        },

        events = {
            refreshGame = function(element)
                local active = IsBreakActive()
                element:SetClass("hidden", not active)

                if active then
                    -- Reset position and minimized state when a new break starts
                    local currentEndTime = GetBreakDoc().data.endTime
                    if currentEndTime ~= lastBreakEndTime then
                        lastBreakEndTime = currentEndTime
                        contentPanel.x = 0
                        contentPanel.y = 0
                        isMinimized = false
                        minimizeButton.text = "-"
                    end

                    -- Update timer via closure
                    local remainingSecs = GetRemainingSeconds()
                    if remainingSecs > 0 then
                        timerLabel.text = FormatTime(remainingSecs)
                        timerLabel:SetClass("collapsed", isMinimized)
                        breakOverLabel:SetClass("collapsed", true)
                    else
                        timerLabel:SetClass("collapsed", true)
                        breakOverLabel:SetClass("collapsed", isMinimized)
                    end
                    toggleButton:SetClass("collapsed", isMinimized)

                    -- Update toggle button text via closure
                    local isBack = GetUserStatus(dmhub.userid) == "back"
                    toggleButton.text = isBack and "Set Away" or "I'm Back"
                end
            end,

            think = function(element)
                element:FireEvent("refreshGame")
            end,
        },

        children = {
            contentPanel,
        },
    }

    return overlayPanel
end

--------------------------------------------------------------------------------
-- OVERLAY INITIALIZATION
--------------------------------------------------------------------------------

-- Track if overlay has been added
local breakOverlayAdded = false

-- Wait for game entry, then poll until HUD is ready before adding overlay
dmhub.RegisterEventHandler("EnterGame", function()
    dmhub.Coroutine(function()
        -- Poll until GameHud is fully ready
        while (not GameHud.instance) or (not GameHud.instance.dialogWorldPanel) or (not GameHud.instance.dialogWorldPanel.valid) do
            coroutine.yield()
        end

        -- Wait a few extra frames for good measure
        for i = 1, 5 do
            coroutine.yield()
        end

        -- Now safe to add overlay
        if not breakOverlayAdded then
            local breakOverlay = CreateBreakOverlay()
            GameHud.instance.dialogWorldPanel:AddChild(breakOverlay)
            breakOverlayAdded = true
        end
    end)
end)

-- Register the dockable panel
DockablePanel.Register{
    name = "Break Time",
    icon = mod.images["panel-icon"],
    dmonly = false,
    minHeight = 100,
    content = function()
        if dmhub.isDM then
            return CreateBreakPanel()
        else
            return CreatePlayerBreakPanel()
        end
    end,
}
