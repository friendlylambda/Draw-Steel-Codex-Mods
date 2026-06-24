local mod = dmhub.GetModLoading()

local CLOCKS_DEBUG = true

local function DebugLog(msg)
    if CLOCKS_DEBUG then
        print("[Clocks] " .. tostring(msg))
    end
end

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local CLOCKS_DOC_ID = "clocks:state"

-- Reference to the active clocks panel for manual refresh
local activeClocksPanel = nil

local function RefreshClocksPanel()
    if activeClocksPanel and activeClocksPanel.valid then
        DebugLog("RefreshClocksPanel: triggering refresh")
        activeClocksPanel:FireEvent("refreshGame")
    else
        DebugLog("RefreshClocksPanel: no valid panel")
    end
end

--------------------------------------------------------------------------------
-- DOCUMENT ACCESS
--------------------------------------------------------------------------------

local function GetClocksDoc()
    return mod:GetDocumentSnapshot(CLOCKS_DOC_ID)
end

-- Initialize document with default structure if needed
local function EnsureDocInitialized()
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil then
        doc:BeginChange()
        doc.data = doc.data or {}
        doc.data.clocks = doc.data.clocks or {}
        doc.data.clockOrder = doc.data.clockOrder or {}
        doc.data.nextId = doc.data.nextId or 1
        doc:CompleteChange("Initialize clocks document")
    end
end

--------------------------------------------------------------------------------
-- CRUD OPERATIONS
--------------------------------------------------------------------------------

-- Create a new clock with default values
local function CreateNewClock()
    local doc = GetClocksDoc()
    doc:BeginChange()

    -- Ensure data structure exists
    doc.data = doc.data or {}
    doc.data.clocks = doc.data.clocks or {}
    doc.data.clockOrder = doc.data.clockOrder or {}
    doc.data.nextId = doc.data.nextId or 1

    local clockId = "clock_" .. doc.data.nextId
    doc.data.nextId = doc.data.nextId + 1

    doc.data.clocks[clockId] = {
        label = "New Clock",
        totalSlices = 3,
        filledSlices = 0,
        visible = false,
    }

    -- Add to order array
    doc.data.clockOrder[#doc.data.clockOrder + 1] = clockId

    doc:CompleteChange("Create new clock")
    DebugLog("Created clock: " .. clockId .. " (total clocks: " .. #doc.data.clockOrder .. ")")
    -- Let monitorGame handle the refresh
    return clockId
end

-- Delete a clock
local function DeleteClock(clockId)
    DebugLog("DeleteClock called for: " .. tostring(clockId))
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil then
        DebugLog("DeleteClock: no data, returning early")
        return
    end

    DebugLog("DeleteClock: before delete, clockOrder has " .. #doc.data.clockOrder .. " items")

    doc:BeginChange()

    -- Remove from clocks table
    doc.data.clocks[clockId] = nil

    -- Remove from order array
    local newOrder = {}
    for _, id in ipairs(doc.data.clockOrder or {}) do
        if id ~= clockId then
            newOrder[#newOrder + 1] = id
        end
    end
    doc.data.clockOrder = newOrder

    DebugLog("DeleteClock: after delete, clockOrder has " .. #newOrder .. " items")

    doc:CompleteChange("Delete clock")
    -- Let monitorGame handle the refresh
end

-- Update clock properties
local function UpdateClock(clockId, updates)
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil or doc.data.clocks[clockId] == nil then
        return
    end

    doc:BeginChange()

    for key, value in pairs(updates) do
        doc.data.clocks[clockId][key] = value
    end

    doc:CompleteChange("Update clock")
end

-- Increment filled slices (right-click)
local function IncrementFilled(clockId)
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil or doc.data.clocks[clockId] == nil then
        return
    end

    local clock = doc.data.clocks[clockId]
    local newFilled = math.min(clock.filledSlices + 1, clock.totalSlices)

    if newFilled ~= clock.filledSlices then
        doc:BeginChange()
        doc.data.clocks[clockId].filledSlices = newFilled
        doc:CompleteChange("Fill clock slice")
    end
end

-- Decrement filled slices (left-click)
local function DecrementFilled(clockId)
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil or doc.data.clocks[clockId] == nil then
        return
    end

    local clock = doc.data.clocks[clockId]
    local newFilled = math.max(clock.filledSlices - 1, 0)

    if newFilled ~= clock.filledSlices then
        doc:BeginChange()
        doc.data.clocks[clockId].filledSlices = newFilled
        doc:CompleteChange("Unfill clock slice")
    end
end

-- Toggle visibility
local function ToggleVisibility(clockId)
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil or doc.data.clocks[clockId] == nil then
        return
    end

    doc:BeginChange()
    doc.data.clocks[clockId].visible = not doc.data.clocks[clockId].visible
    doc:CompleteChange("Toggle clock visibility")
end

--------------------------------------------------------------------------------
-- CLOCK VISUAL
--------------------------------------------------------------------------------

local function CreateClockVisual(totalSlices, filledSlices, size)
    totalSlices = totalSlices or 0
    filledSlices = filledSlices or 0
    local imageName = string.format("clock-%d-%d", totalSlices, filledSlices)
    local clockImage = mod.images[imageName]

    if clockImage then
        return gui.Panel{
            width = size,
            height = size,
            bgimage = clockImage,
            bgcolor = "white",
            halign = "center",
        }
    else
        -- Fallback: text display
        return gui.Label{
            text = string.format("%d/%d", filledSlices, totalSlices),
            width = size,
            height = size,
            fontSize = 16,
            textAlignment = "center",
            halign = "center",
            valign = "center",
            bgcolor = "#333333",
            borderWidth = 1,
            borderColor = "#666666",
        }
    end
end

--------------------------------------------------------------------------------
-- EDIT CLOCK DIALOG
--------------------------------------------------------------------------------

local function ShowEditClockDialog(clockId)
    local doc = GetClocksDoc()
    if doc.data == nil or doc.data.clocks == nil or doc.data.clocks[clockId] == nil then
        return
    end

    local clock = doc.data.clocks[clockId]
    local labelInput = clock.label
    local slicesInput = clock.totalSlices

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

    -- Slices display: themed bordered surface (no inline colors)
    local slicesLabel = gui.Label{
        classes = {"bordered"},
        text = tostring(slicesInput),
        fontSize = 24,
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
            slicesInput = math.max(3, slicesInput - 1)
            slicesLabel.text = tostring(slicesInput)
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
            slicesInput = math.min(16, slicesInput + 1)
            slicesLabel.text = tostring(slicesInput)
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

        -- This modal lives outside any themed container, so it owns its own
        -- cascade root via ThemeEngine.GetStyles().
        styles = ThemeEngine.GetStyles(),

        -- Title
        gui.Label{
            classes = {"modalTitle"},
            text = "Edit Clock",
            fontSize = 20,
            vmargin = 8,
        },

        -- Label section
        gui.Label{
            classes = {"modalMessage"},
            text = "Label:",
            fontSize = 14,
            width = "100%",
            textAlignment = "center",
            vmargin = 8,
        },

        labelField,

        -- Slices section
        gui.Label{
            classes = {"modalMessage"},
            text = "Slices:",
            fontSize = 14,
            width = "100%",
            textAlignment = "center",
            vmargin = 8,
        },

        -- Slices input row
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            vmargin = 8,

            children = {
                decreaseButton,
                slicesLabel,
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

            -- Delete button (themed-neutral; a composition class can't recolor
            -- a button surface)
            gui.Button{
                width = 80,
                height = 36,
                hmargin = 4,
                text = "Delete",
                fontSize = 14,

                click = function(element)
                    DeleteClock(clockId)
                    gui.CloseModal()
                end,
            },

            -- Cancel button
            gui.Button{
                width = 80,
                height = 36,
                hmargin = 4,
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
                hmargin = 4,
                text = "Save",
                fontSize = 14,

                click = function(element)
                    UpdateClock(clockId, {
                        label = labelInput,
                        totalSlices = slicesInput,
                        -- Clamp filled slices if total was reduced
                        filledSlices = math.min(doc.data.clocks[clockId].filledSlices, slicesInput),
                    })
                    gui.CloseModal()
                end,
            },
        },

        -- Close button (X)
        gui.Button{
            classes = {"closeButton"},
            floating = true,
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
-- CLOCK CELL COMPONENT
--------------------------------------------------------------------------------

local function CreateClockCell(clock, clockId, isDM)
    local size = 80

    -- Create the clock visual
    local clockVisual = CreateClockVisual(clock.totalSlices, clock.filledSlices, size)

    -- Visual container with click handlers (DM only)
    -- Left-click = fill, Right-click = unfill
    local visualContainer
    if isDM then
        visualContainer = gui.Panel{
            width = size,
            height = size,
            halign = "center",

            press = function(element)
                if dmhub.modKeys.ctrl then
                    ShowEditClockDialog(clockId)
                else
                    IncrementFilled(clockId)
                end
            end,

            rightClick = function(element)
                DecrementFilled(clockId)
            end,

            children = { clockVisual },
        }
    else
        visualContainer = gui.Panel{
            width = size,
            height = size,
            halign = "center",
            children = { clockVisual },
        }
    end

    -- Eye toggle (DM only)
    local eyeToggle = nil
    if isDM then
        eyeToggle = gui.Panel{
            width = 20,
            height = 20,
            bgcolor = "white",
            bgimage = clock.visible and "ui-icons/eye.png" or "ui-icons/eye-closed.png",
            opacity = 0.8,
            halign = "right",
            valign = "top",
            floating = true,
            x = -2,
            y = 2,

            click = function(element)
                ToggleVisibility(clockId)
            end,
        }
    end

    -- Label (clickable for DM to open editor)
    local labelElement
    local displayLabel = clock.label
    if isDM and (displayLabel == nil or displayLabel == "") then
        displayLabel = "(unnamed)"
    end

    if isDM then
        labelElement = gui.Label{
            text = displayLabel,
            fontSize = 12,
            width = 100,
            minWidth = 30,
            height = "auto",
            minHeight = 12,
            halign = "center",
            textAlignment = "center",
            vmargin = 4,
            color = "#cccccc",

            click = function(element)
                ShowEditClockDialog(clockId)
            end,
        }
    else
        labelElement = gui.Label{
            text = displayLabel,
            fontSize = 12,
            width = 100,
            minWidth = 30,
            height = "auto",
            minHeight = 12,
            halign = "center",
            textAlignment = "center",
            vmargin = 4,
            color = "#cccccc",
        }
    end

    -- Build cell children
    local cellChildren = { visualContainer, labelElement }
    if eyeToggle then
        cellChildren[#cellChildren + 1] = eyeToggle
    end

    return gui.Panel{
        width = 110,
        height = "auto",
        flow = "vertical",
        halign = "center",
        vmargin = 8,
        hmargin = 4,

        children = cellChildren,
    }
end

--------------------------------------------------------------------------------
-- ADD CLOCK BUTTON
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
                    CreateNewClock()
                end,
            },
        },
    }
end

--------------------------------------------------------------------------------
-- MAIN PANEL
--------------------------------------------------------------------------------

local function CreateClocksPanel()
    -- STEP 4: container + add button via buildRows (no clock cells yet)
    local doc = GetClocksDoc()
    local lastHash = "__uninitialized__"
    local isDM = dmhub.isDM

    DebugLog("CreateClocksPanel: doc.path = " .. tostring(doc.path))

    -- Ensure document is initialized
    EnsureDocInitialized()

    local clocksContainer = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
    }

    local CELLS_PER_ROW = 3

    local noClocksLabel = gui.Label{
        classes = {"collapsed"},
        text = "No clocks visible",
        fontSize = 14,
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        color = "#888888",
        vmargin = 16,
    }

    local function buildHash()
        local docData = GetClocksDoc().data
        if docData == nil or docData.clocks == nil then
            return ""
        end
        local parts = {}
        for _, clockId in ipairs(docData.clockOrder or {}) do
            local clock = docData.clocks[clockId]
            if clock then
                parts[#parts + 1] = string.format("%s:%s:%d:%d:%s",
                    clockId, clock.label or "", clock.totalSlices or 0,
                    clock.filledSlices or 0, tostring(clock.visible))
            end
        end
        return table.concat(parts, "|")
    end

    local function buildRows()
        local docData = GetClocksDoc().data
        local cells = {}
        local visibleCount = 0

        if docData and docData.clockOrder then
            for i, clockId in ipairs(docData.clockOrder) do
                local clock = docData.clocks[clockId]
                if clock then
                    if isDM or clock.visible then
                        local cell = CreateClockCell(clock, clockId, isDM)
                        cells[#cells + 1] = cell
                        visibleCount = visibleCount + 1
                    end
                end
            end
        end

        if isDM then
            cells[#cells + 1] = CreateAddButton()
        end

        local rows = {}
        local currentRowCells = {}

        for i, cell in ipairs(cells) do
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

        return rows, visibleCount
    end

    local mainPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        vpad = 8,
        hpad = 8,

        monitorGame = doc.path,

        events = {
            refreshGame = function(element)
                DebugLog("refreshGame triggered")
                local currentHash = buildHash()
                if currentHash ~= lastHash then
                    lastHash = currentHash
                    local rows, visibleCount = buildRows()
                    clocksContainer.children = rows

                    if not isDM and visibleCount == 0 then
                        noClocksLabel:SetClass("collapsed", false)
                    else
                        noClocksLabel:SetClass("collapsed", true)
                    end
                end
            end,
        },

        children = {
            noClocksLabel,
            clocksContainer,
        },
    }

    activeClocksPanel = mainPanel
    mainPanel:FireEvent("refreshGame")

    return mainPanel
end

--------------------------------------------------------------------------------
-- DOCKABLE PANEL REGISTRATION
--------------------------------------------------------------------------------

DockablePanel.Register{
    name = "Clocks",
    icon = mod.images["panel-icon"],
    dmonly = false,
    minHeight = 150,
    vscroll = true,
    content = function()
        return CreateClocksPanel()
    end,
}
