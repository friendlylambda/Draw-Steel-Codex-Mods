local mod = dmhub.GetModLoading()

local TIMERS_DEBUG = true

local function DebugLog(msg)
    if TIMERS_DEBUG then
        print("[Timers] " .. tostring(msg))
    end
end

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local TIMERS_DOC_ID = "timers:state"

-- Reference to the active timers panel for manual refresh
local activeTimersPanel = nil

local function RefreshTimersPanel()
    if activeTimersPanel and activeTimersPanel.valid then
        DebugLog("RefreshTimersPanel: triggering refresh")
        activeTimersPanel:FireEvent("refreshGame")
    else
        DebugLog("RefreshTimersPanel: no valid panel")
    end
end

--------------------------------------------------------------------------------
-- DOCUMENT ACCESS
--------------------------------------------------------------------------------

local function GetTimersDoc()
    return mod:GetDocumentSnapshot(TIMERS_DOC_ID)
end

-- Initialize document with default structure if needed
local function EnsureDocInitialized()
    local doc = GetTimersDoc()
    if doc.data == nil or doc.data.timers == nil then
        doc:BeginChange()
        doc.data = doc.data or {}
        doc.data.timers = doc.data.timers or {}
        doc.data.timerOrder = doc.data.timerOrder or {}
        doc.data.nextId = doc.data.nextId or 1
        doc:CompleteChange("Initialize timers document")
    end
end

--------------------------------------------------------------------------------
-- TIME HELPERS
--------------------------------------------------------------------------------

local function FormatTimeRemaining(secondsLeft)
    if secondsLeft <= 0 then
        return "0:00"
    end
    local minutes = math.floor(secondsLeft / 60)
    local seconds = math.floor(secondsLeft % 60)
    return string.format("%d:%02d", minutes, seconds)
end

-- Format a duration in seconds for compact display (e.g. "1m", "2m 30s", "30s")
local function FormatDuration(totalSeconds)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    if minutes > 0 and seconds > 0 then
        return tostring(minutes) .. "m " .. tostring(seconds) .. "s"
    elseif minutes > 0 then
        return tostring(minutes) .. "m"
    else
        return tostring(seconds) .. "s"
    end
end

-- Returns "idle", "running", or "expired"
local function GetTimerState(timer)
    if timer.endTime == nil then
        return "idle"
    end
    if dmhub.serverTime < timer.endTime then
        return "running"
    end
    return "expired"
end

--------------------------------------------------------------------------------
-- CRUD OPERATIONS
--------------------------------------------------------------------------------

-- Create a new timer with default values
local function CreateNewTimer()
    local doc = GetTimersDoc()
    doc:BeginChange()

    -- Ensure data structure exists
    doc.data = doc.data or {}
    doc.data.timers = doc.data.timers or {}
    doc.data.timerOrder = doc.data.timerOrder or {}
    doc.data.nextId = doc.data.nextId or 1

    local timerId = "timer_" .. doc.data.nextId
    doc.data.nextId = doc.data.nextId + 1

    doc.data.timers[timerId] = {
        label = "New Timer",
        durationSeconds = 60,
        triggerType = "manual",
        endTime = nil,
    }

    -- Add to order array
    doc.data.timerOrder[#doc.data.timerOrder + 1] = timerId

    doc:CompleteChange("Create new timer")
    DebugLog("Created timer: " .. timerId .. " (total timers: " .. #doc.data.timerOrder .. ")")
    return timerId
end

-- Delete a timer
local function DeleteTimer(timerId)
    DebugLog("DeleteTimer called for: " .. tostring(timerId))
    local doc = GetTimersDoc()
    if doc.data == nil or doc.data.timers == nil then
        DebugLog("DeleteTimer: no data, returning early")
        return
    end

    doc:BeginChange()

    -- Remove from timers table
    doc.data.timers[timerId] = nil

    -- Remove from order array
    local newOrder = {}
    for _, id in ipairs(doc.data.timerOrder or {}) do
        if id ~= timerId then
            newOrder[#newOrder + 1] = id
        end
    end
    doc.data.timerOrder = newOrder

    doc:CompleteChange("Delete timer")
end

-- Update timer properties
local function UpdateTimer(timerId, updates)
    local doc = GetTimersDoc()
    if doc.data == nil or doc.data.timers == nil or doc.data.timers[timerId] == nil then
        return
    end

    doc:BeginChange()

    for key, value in pairs(updates) do
        doc.data.timers[timerId][key] = value
    end

    doc:CompleteChange("Update timer")
end

-- Toggle a timer between running and stopped
local function ToggleTimer(timerId)
    local doc = GetTimersDoc()
    if doc.data == nil or doc.data.timers == nil or doc.data.timers[timerId] == nil then
        return
    end

    local timer = doc.data.timers[timerId]
    doc:BeginChange()

    if timer.endTime ~= nil then
        -- Stop/reset the timer
        doc.data.timers[timerId].endTime = nil
        DebugLog("Stopped timer: " .. timerId)
    else
        -- Start the timer
        doc.data.timers[timerId].endTime = dmhub.serverTime + timer.durationSeconds
        DebugLog("Started timer: " .. timerId .. " for " .. timer.durationSeconds .. " seconds")
    end

    doc:CompleteChange("Toggle timer")
end

--------------------------------------------------------------------------------
-- EDIT TIMER DIALOG
--------------------------------------------------------------------------------

local function ShowEditTimerDialog(timerId)
    local doc = GetTimersDoc()
    if doc.data == nil or doc.data.timers == nil or doc.data.timers[timerId] == nil then
        return
    end

    local timer = doc.data.timers[timerId]
    local labelInput = timer.label
    local durationInput = timer.durationSeconds

    -- Label input field
    local labelField = gui.Input{
        width = 200,
        height = 32,
        fontSize = 14,
        text = labelInput,
        halign = "center",

        change = function(element)
            labelInput = element.text
        end,
    }

    -- Duration display label
    local durationLabel = gui.Label{
        text = FormatDuration(durationInput),
        fontSize = 24,
        width = 140,
        height = 40,
        halign = "center",
        valign = "center",
        textAlignment = "center",
        bgcolor = "#333333",
        borderWidth = 1,
        borderColor = "#666666",
    }

    local decreaseButton = gui.Button{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        hmargin = 4,
        text = "-",
        fontSize = 24,

        click = function(element)
            durationInput = math.max(30, durationInput - 30)
            durationLabel.text = FormatDuration(durationInput)
        end,
    }

    local increaseButton = gui.Button{
        width = 40,
        height = 40,
        halign = "center",
        valign = "center",
        hmargin = 4,
        text = "+",
        fontSize = 24,

        click = function(element)
            durationInput = math.min(7200, durationInput + 30)
            durationLabel.text = FormatDuration(durationInput)
        end,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        width = 320,
        height = "auto",
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
            text = "Edit Timer",
            fontSize = 20,
            bold = true,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 8,
        },

        -- Label section
        gui.Label{
            text = "Label:",
            fontSize = 14,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 8,
        },

        labelField,

        -- Duration section
        gui.Label{
            text = "Duration:",
            fontSize = 14,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 8,
        },

        -- Duration input row
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            vmargin = 8,

            children = {
                decreaseButton,
                durationLabel,
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

            -- Delete button (red)
            gui.Button{
                width = 80,
                height = 36,
                hmargin = 8,
                text = "Delete",
                fontSize = 14,
                bgcolor = "#aa3333",

                click = function(element)
                    DeleteTimer(timerId)
                    gui.CloseModal()
                end,
            },

            -- Cancel button
            gui.Button{
                width = 80,
                height = 36,
                hmargin = 8,
                text = "Cancel",
                fontSize = 14,

                click = function(element)
                    gui.CloseModal()
                end,
            },

            -- Save button
            gui.Button{
                width = 80,
                height = 36,
                hmargin = 8,
                text = "Save",
                fontSize = 14,

                click = function(element)
                    UpdateTimer(timerId, {
                        label = labelInput,
                        durationSeconds = durationInput,
                    })
                    gui.CloseModal()
                end,
            },
        },

    }

    gui.ShowModal(dialogPanel)
end

--------------------------------------------------------------------------------
-- TIMER CELL COMPONENT (for the GM panel)
--------------------------------------------------------------------------------

-- Creates a timer cell and populates refs table for closure-based updates.
-- refs[timerId] = { displayLabel, visual } for live time updates without rebuild.
local function CreateTimerCell(timer, timerId, refs)
    local size = 80
    local state = GetTimerState(timer)

    -- Determine initial display text
    local displayText

    if state == "expired" then
        displayText = "Done!"
    else
        displayText = FormatDuration(timer.durationSeconds)
    end

    local displayLabel = gui.Button{
        text = displayText,
        width = 84,
        height = 36,
        fontSize = 18,
        bold = true,
        halign = "center",
        valign = "center",
        classes = {state == "running" and "hidden" or "visible"},
        styles = {
            { selectors = {"hidden"}, collapsed = 1 },
        },
        click = function(element)
            ToggleTimer(timerId)
        end,
    }

    -- Stop button shown when timer is running
    local stopIcon = gui.Button{
        width = 28,
        height = 28,
        halign = "center",
        valign = "center",
        bgcolor = "#cc3333",
        cornerRadius = 4,
        text = "",
        classes = {state == "running" and "visible" or "hidden"},
        styles = {
            { selectors = {"hidden"}, collapsed = 1 },
        },
        click = function(element)
            ToggleTimer(timerId)
        end,
    }

    local visualPanel = gui.Panel{
        width = size,
        height = size,
        halign = "center",
        bgcolor = "#333333",
        borderWidth = 2,
        borderColor = "#666666",
        cornerRadius = 8,

        classes = {state == "running" and "timer-running" or state == "expired" and "timer-expired" or "timer-idle"},

        styles = {
            {
                selectors = {"timer-idle"},
                bgcolor = "#333333",
                borderColor = "#666666",
            },
            {
                selectors = {"timer-running"},
                bgcolor = "#2d5a2d",
                borderColor = "#44cc44",
            },
            {
                selectors = {"timer-expired"},
                bgcolor = "#5a2d2d",
                borderColor = "#663333",
            },
        },

        children = { displayLabel, stopIcon },
    }

    -- Store refs for closure-based time updates
    refs[timerId] = {
        displayLabel = displayLabel,
        stopIcon = stopIcon,
        visual = visualPanel,
    }

    -- Label (clickable to open editor)
    local labelElement = gui.Label{
        text = timer.label,
        fontSize = 12,
        width = 100,
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 4,
        color = "#e0e0e0",

        click = function(element)
            ShowEditTimerDialog(timerId)
        end,
    }

    return gui.Panel{
        width = 110,
        height = "auto",
        flow = "vertical",
        halign = "center",
        vmargin = 8,
        hmargin = 4,

        children = { visualPanel, labelElement },
    }
end

--------------------------------------------------------------------------------
-- ADD TIMER BUTTON
--------------------------------------------------------------------------------

local function CreateAddButton()
    return gui.Panel{
        width = 110,
        height = 120,
        halign = "center",
        valign = "top",
        vmargin = 8,
        hmargin = 4,

        children = {
            gui.Button{
                width = 60,
                height = 60,
                halign = "center",
                valign = "center",
                text = "+",
                fontSize = 32,

                click = function(element)
                    CreateNewTimer()
                end,
            },
        },
    }
end

--------------------------------------------------------------------------------
-- MAIN PANEL (GM-only)
--------------------------------------------------------------------------------

local function CreateTimersPanel()
    local doc = GetTimersDoc()
    local lastStructureHash = "__uninitialized__"

    DebugLog("CreateTimersPanel: doc.path = " .. tostring(doc.path))

    -- Ensure document is initialized
    EnsureDocInitialized()

    local timersContainer = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
    }

    local CELLS_PER_ROW = 3

    local noTimersLabel = gui.Label{
        classes = {"collapsed"},
        text = "Click + to create a new countdown timer. Click a timer's name to edit it, or the number to start/stop it.",
        fontSize = 14,
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        color = "#e0e0e0",
        vmargin = 16,
    }

    -- Closure refs for live time updates (avoids full rebuild every second)
    local timerRefs = {}

    -- Structure hash: changes when timers are added/removed/edited or start/stop.
    -- Does NOT change every second while a timer is running.
    local function buildStructureHash()
        local docData = GetTimersDoc().data
        if docData == nil or docData.timers == nil then
            return ""
        end
        local parts = {}
        for _, timerId in ipairs(docData.timerOrder or {}) do
            local timer = docData.timers[timerId]
            if timer then
                parts[#parts + 1] = string.format("%s:%s:%d:%s",
                    timerId, timer.label or "", timer.durationSeconds or 0,
                    tostring(timer.endTime or "nil"))
            end
        end
        return table.concat(parts, "|")
    end

    local function buildRows()
        timerRefs = {}
        local docData = GetTimersDoc().data
        local cells = {}

        if docData and docData.timerOrder then
            for _, timerId in ipairs(docData.timerOrder) do
                local timer = docData.timers[timerId]
                if timer then
                    local cell = CreateTimerCell(timer, timerId, timerRefs)
                    cells[#cells + 1] = cell
                end
            end
        end

        cells[#cells + 1] = CreateAddButton()

        local rows = {}
        local currentRowCells = {}

        for _, cell in ipairs(cells) do
            currentRowCells[#currentRowCells + 1] = cell

            if #currentRowCells == CELLS_PER_ROW then
                rows[#rows + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    children = currentRowCells,
                }
                currentRowCells = {}
            end
        end

        if #currentRowCells > 0 then
            rows[#rows + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                children = currentRowCells,
            }
        end

        return rows, #cells - 1  -- subtract 1 for the add button
    end

    -- Update counters with the correct ui (formatted duration or stop button)
    local function updatePanelDisplays()
        local docData = GetTimersDoc().data
        if docData == nil or docData.timers == nil then return end

        for timerId, refs in pairs(timerRefs) do
            local timer = docData.timers[timerId]
            if timer then
                local state = GetTimerState(timer)
                local running = state == "running"
                if state == "expired" then
                    refs.displayLabel.text = "Done!"
                else
                    refs.displayLabel.text = FormatDuration(timer.durationSeconds)
                end
                refs.displayLabel:SetClass("hidden", running)
                refs.stopIcon:SetClass("hidden", not running)
                refs.visual:SetClass("timer-idle", state == "idle")
                refs.visual:SetClass("timer-running", running)
                refs.visual:SetClass("timer-expired", state == "expired")
            end
        end
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
                DebugLog("refreshGame triggered")
                local currentHash = buildStructureHash()
                if currentHash ~= lastStructureHash then
                    lastStructureHash = currentHash
                    local rows, timerCount = buildRows()
                    timersContainer.children = rows
                    noTimersLabel:SetClass("collapsed", timerCount > 0)
                else
                    updatePanelDisplays()
                end
            end,

            think = function(element)
                -- Check structural changes first
                local currentHash = buildStructureHash()
                if currentHash ~= lastStructureHash then
                    lastStructureHash = currentHash
                    local rows, timerCount = buildRows()
                    timersContainer.children = rows
                    noTimersLabel:SetClass("collapsed", timerCount > 0)
                else
                    -- Just update time displays for running timers
                    updatePanelDisplays()
                end
            end,
        },

        children = {
            noTimersLabel,
            timersContainer,
        },
    }

    activeTimersPanel = mainPanel
    mainPanel:FireEvent("refreshGame")

    return mainPanel
end

--------------------------------------------------------------------------------
-- DOCKABLE PANEL REGISTRATION
--------------------------------------------------------------------------------

DockablePanel.Register{
    name = "Countdown Timers",
    icon = mod.images["panel-icon"],
    dmonly = true,
    minHeight = 150,
    vscroll = true,
    content = function()
        return CreateTimersPanel()
    end,
}

--------------------------------------------------------------------------------
-- COUNTDOWN OVERLAY (visible to all players)
--------------------------------------------------------------------------------

local function CreateCountdownOverlay()
    local doc = GetTimersDoc()

    local overlayPanel

    local cardsContainer = gui.Panel{
        width = 280,
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        hmargin = 20,
        vmargin = 20,
    }

    local function rebuildCards()
        local currentDoc = GetTimersDoc()
        if currentDoc.data == nil or currentDoc.data.timers == nil then
            overlayPanel:SetClass("hidden", true)
            cardsContainer.children = {}
            return
        end

        local cards = {}
        for _, timerId in ipairs(currentDoc.data.timerOrder or {}) do
            local timer = currentDoc.data.timers[timerId]
            if timer and timer.endTime ~= nil then
                local state = GetTimerState(timer)
                local remaining = state == "running" and (timer.endTime - dmhub.serverTime) or 0
                local isExpired = state == "expired"

                local barColor = isExpired and "#663333" or "#44cc44"
                local textColor = isExpired and "#663333" or "#44cc44"
                local displayText = isExpired and "TIME'S UP" or FormatTimeRemaining(remaining)

                cards[#cards + 1] = gui.Panel{
                    width = 280,
                    height = "auto",
                    flow = "vertical",
                    halign = "right",
                    classes = {"framedPanel"},
                    styles = { Styles.Panel },
                    vpad = 16,
                    hpad = 20,
                    vmargin = 8,

                    children = {
                        gui.Panel{
                            width = "100%",
                            height = 6,
                            bgcolor = barColor,
                            cornerRadius = 3,
                        },
                        gui.Label{
                            width = "100%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            text = timer.label,
                            fontSize = 16,
                            bold = true,
                            color = "#cccccc",
                            vmargin = 4,
                        },
                        gui.Label{
                            width = "100%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            text = displayText,
                            fontSize = 36,
                            bold = true,
                            color = textColor,
                            vmargin = 4,
                        },
                    },
                }
            end
        end

        if #cards == 0 then
            overlayPanel:SetClass("hidden", true)
            cardsContainer.children = {}
        else
            cardsContainer.children = cards
            overlayPanel:SetClass("hidden", false)
        end
    end

    overlayPanel = gui.Panel{
        classes = {"timers-overlay", "hidden"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        floating = true,

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
                rebuildCards()
            end,

            think = function(element)
                rebuildCards()
            end,
        },

        children = {
            cardsContainer,
        },
    }

    return overlayPanel
end

-- Attach overlay to HUD using EnterGame coroutine pattern

local overlayAdded = false

dmhub.RegisterEventHandler("EnterGame", function()
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
            local overlay = CreateCountdownOverlay()
            GameHud.instance.dialogWorldPanel:AddChild(overlay)
            overlayAdded = true
        end
    end)
end)
