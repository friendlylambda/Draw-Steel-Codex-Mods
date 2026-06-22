local mod = dmhub.GetModLoading()

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local DOC_ID = "safetycards:events"

local CARD_COLORS = {
    red    = { label = "Red Card",    hex = "#ff4444" },
    yellow = { label = "Yellow Card", hex = "#ffcc00" },
    green  = { label = "Green Card",  hex = "#44cc44" },
}

local function GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

------------------------------------------------------------
-- Settings
------------------------------------------------------------

setting{
    id = "safetycards:anonymous",
    description = "Safety Cards: Make Your Cards Anonymous",
    editor = "check",
    default = false,
    storage = "preference",
    section = "General",
    help = "When enabled, your name will not be shown when you play a safety card.",
}

setting{
    id = "safetycards:showtoall",
    description = "Safety Cards: Show Played Cards to All Players",
    editor = "check",
    default = false,
    storage = "preference",
    section = "General",
    help = "When enabled, the safety card notification will be shown to all players, not just the GM.",
}

------------------------------------------------------------
-- Card Play Function
------------------------------------------------------------

local function PlayCard(color)
    local doc = GetDoc()
    doc:BeginChange()
    doc.data = doc.data or {}
    if doc.data.events == nil then
        doc.data.events = {}
    end
    local anonymous = dmhub.GetSettingValue("safetycards:anonymous")
    local showToAll = dmhub.GetSettingValue("safetycards:showtoall")
    doc.data.events[dmhub.userid] = {
        color = color,
        senderName = (not anonymous) and dmhub.GetSessionInfo(dmhub.userid).displayName or nil,
        showToAll = showToAll,
        timestamp = dmhub.serverTime,
    }
    doc:CompleteChange("Play safety card")
end

------------------------------------------------------------
-- Command Handler + Keybinds
------------------------------------------------------------

Commands.safetycard = function(str)
    local color = string.lower(str or "")
    if CARD_COLORS[color] then
        PlayCard(color)
    end
end


------------------------------------------------------------
-- Dockable Sidebar Panel
------------------------------------------------------------

local function CreateCardButton(color)
    local info = CARD_COLORS[color]
    return gui.Button{
        width = 64,
        height = 80,
        halign = "center",
        valign = "center",
        hmargin = 6,
        bgcolor = info.hex,
        text = info.label,
        fontSize = 13,
        bold = true,
        color = (color == "yellow") and "#000000" or "#ffffff",
        click = function(element)
            PlayCard(color)
        end,
    }
end

DockablePanel.Register{
    name = "Safety Cards",
    icon = mod.images["panel-icon"],
    dmonly = false,
    minHeight = 100,

    content = function()
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            vpad = 8,

            children = {
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "center",
                    vmargin = 4,
                    children = {
                        CreateCardButton("red"),
                        CreateCardButton("yellow"),
                        CreateCardButton("green"),
                    },
                },
            },
        }
    end,
}

------------------------------------------------------------
-- Notification Overlay
------------------------------------------------------------

local function CreateCardNotification(userid, event, onDismiss)
    local info = CARD_COLORS[event.color] or CARD_COLORS.red

    local children = {
        gui.Panel{
            width = "100%",
            height = 6,
            bgcolor = info.hex,
            cornerRadius = 3,
        },
        gui.Label{
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            text = info.label,
            fontSize = 28,
            bold = true,
            color = info.hex,
            vmargin = 8,
        },
    }

    if event.senderName then
        children[#children+1] = gui.Label{
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            text = "Played by: " .. event.senderName,
            fontSize = 16,
            color = "#cccccc",
            vmargin = 4,
        }
    end

    children[#children+1] = gui.Label{
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        text = "Click to dismiss",
        fontSize = 12,
        color = "#999999",
        vmargin = 8,
    }

    return gui.Panel{
        width = 280,
        height = "auto",
        flow = "vertical",
        halign = "right",
        classes = {"framedPanel"},
        styles = { Styles.Panel },
        vpad = 16,
        hpad = 20,
        vmargin = 8,
        interactable = true,

        press = function(element)
            onDismiss()
        end,

        children = children,
    }
end

local function CreateNotificationOverlay()
    local doc = GetDoc()
    local loadTime = dmhub.serverTime
    local dismissedEvents = {}  -- dismissedEvents[userid] = timestamp

    local cardsContainer = gui.Panel{
        width = 280,
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        hmargin = 20,
        vmargin = 20,
    }

    local lastHash = ""
    local overlayPanel  -- forward declare for use in rebuild

    local function GetVisibleEvents()
        local currentDoc = GetDoc()
        if currentDoc.data == nil or currentDoc.data.events == nil then
            return {}
        end

        local visible = {}
        for userid, event in pairs(currentDoc.data.events) do
            local dismissed = dismissedEvents[userid] or 0
            local canSee = event.showToAll or dmhub.isDM
            if event.timestamp > dismissed and event.timestamp > loadTime and canSee then
                visible[#visible+1] = { userid = userid, event = event }
            end
        end

        table.sort(visible, function(a, b)
            return a.event.timestamp < b.event.timestamp
        end)

        return visible
    end

    local function buildHash(visibleList)
        local parts = {}
        for _, entry in ipairs(visibleList) do
            parts[#parts+1] = entry.userid .. ":" .. entry.event.color .. ":" .. entry.event.timestamp
        end
        return table.concat(parts, ",")
    end

    local function rebuildCards()
        local visibleList = GetVisibleEvents()
        lastHash = buildHash(visibleList)

        if #visibleList == 0 then
            overlayPanel:SetClass("hidden", true)
            cardsContainer.children = {}
            return
        end

        local cards = {}
        for _, entry in ipairs(visibleList) do
            local uid = entry.userid
            local evt = entry.event
            local card = CreateCardNotification(uid, evt, function()
                dismissedEvents[uid] = evt.timestamp
                rebuildCards()
            end)
            cards[#cards+1] = card
        end

        cardsContainer.children = cards
        overlayPanel:SetClass("hidden", false)
    end

    overlayPanel = gui.Panel{
        classes = {"safetycards-overlay", "hidden"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        floating = true,
        bgcolor = "#00000088",

        monitorGame = doc.path,

        styles = {
            {
                selectors = {"hidden"},
                collapsed = 1,
            },
        },

        events = {
            refreshGame = function(element)
                local visibleList = GetVisibleEvents()
                local currentHash = buildHash(visibleList)

                if currentHash == lastHash then
                    return
                end

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
            local overlay = CreateNotificationOverlay()
            GameHud.instance.dialogWorldPanel:AddChild(overlay)
            overlayAdded = true
        end
    end)
end)
