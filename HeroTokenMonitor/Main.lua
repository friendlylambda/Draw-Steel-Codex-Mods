-- Hero Token Activity Monitor
-- Alerts the GM if no hero token activity occurs for a configurable time

local HTM_DEBUG = false

local mod = dmhub.GetModLoading()

-- Settings
setting{
    id = "herotokenmonitor:repeat",
    description = "Repeat reminder every [Wait Time] minutes",
    editor = "check",
    default = true,
    storage = "game",
    section = "General",
    dmonly = true,
    help = "When enabled, the reminder will repeat every [Wait Time] minutes until hero tokens are used.",
}

setting{
    id = "herotokenmonitor:wait_minutes",
    description = "Wait Time (minutes, min: 5)",
    editor = "input",
    default = "10",
    storage = "game",
    section = "General",
    dmonly = true,
    help = "How many minutes of inactivity before sending a reminder. Minimum 5 minutes.",
}

setting{
    id = "herotokenmonitor:enabled",
    description = "Enable Hero Token Reminder",
    editor = "check",
    default = true,
    storage = "game",
    section = "General",
    dmonly = true,
    help = "When enabled, the GM will receive a chat reminder if no hero tokens are spent for the configured time.",
}

-- Constants
local CHECK_INTERVAL = 30         -- Check every 30 seconds

-- Track alert state locally
local lastAlertTime = 0
local hasAlertedThisCycle = false  -- Reset when activity detected

-- Check if any non-DM players are online
local function AnyPlayersOnline()
    local users = dmhub.users
    for _, userid in ipairs(users) do
        if not dmhub.IsUserDM(userid) then
            local sessionInfo = dmhub.GetSessionInfo(userid)
            if sessionInfo and not sessionInfo.loggedOut and sessionInfo.timeSinceLastContact < 35 then
                return true
            end
        end
    end
    return false
end

-- Parse "when" string to get minutes ago
local function ParseWhenString(when)
    -- Check for hours (singular or plural): "an hour ago", "2 hours ago"
    if when:find("hour") then
        local num = tonumber(when:match("(%d+)")) or 1  -- "an hour" = 1
        return num * 60
    end

    -- Check for minutes: "43 minutes ago"
    if when:find("minute") then
        local num = tonumber(when:match("(%d+)"))
        if num then
            return num
        end
    end

    -- "just now" or unparseable -> treat as recent
    return 0
end

-- Get minutes since most recent hero token activity (nil if no history)
local function GetMinutesSinceLastActivity()
    local history = CharacterResource.GetGlobalResourceHistory(CharacterResource.heroTokenId)

    -- Find the last entry (highest key = most recent)
    local lastKey = nil
    for k, _ in pairs(history) do
        if lastKey == nil or k > lastKey then
            lastKey = k
        end
    end

    if lastKey == nil then
        if HTM_DEBUG then print("[HTM Debug] No hero token history") end
        return nil
    end

    local lastEntry = history[lastKey]
    local whenStr = lastEntry.when or ""
    local minutes = ParseWhenString(whenStr)
    if HTM_DEBUG then print("[HTM Debug] Last entry when='" .. whenStr .. "' -> " .. minutes .. " minutes") end
    return minutes
end

-- Create the inactivity checker panel (invisible, just runs periodic checks)
local function CreateInactivityChecker()
    return gui.Panel{
        width = 0,
        height = 0,
        thinkTime = CHECK_INTERVAL,

        events = {
            think = function(element)
                if HTM_DEBUG then print("[HTM Debug] think fired") end

                -- Only run for the GM
                if not dmhub.isDM then
                    if HTM_DEBUG then print("[HTM Debug] Not DM, skipping") end
                    return
                end

                -- Check if enabled
                local enabled = dmhub.GetSettingValue("herotokenmonitor:enabled")
                if not enabled then
                    if HTM_DEBUG then print("[HTM Debug] Disabled, skipping") end
                    return
                end

                -- Skip if no players online
                if not AnyPlayersOnline() then
                    if HTM_DEBUG then print("[HTM Debug] No players online, skipping") end
                    return
                end

                -- Get threshold from settings (minimum 5 minutes)
                local thresholdMinutes = tonumber(dmhub.GetSettingValue("herotokenmonitor:wait_minutes")) or 10
                thresholdMinutes = math.max(thresholdMinutes, 5)
                if HTM_DEBUG then print("[HTM Debug] thresholdMinutes =", thresholdMinutes) end

                -- Get minutes since last hero token activity
                local minutesSinceActivity = GetMinutesSinceLastActivity()
                if minutesSinceActivity == nil then
                    if HTM_DEBUG then print("[HTM Debug] No hero token history, skipping") end
                    return
                end

                if HTM_DEBUG then print("[HTM Debug] minutesSinceActivity =", minutesSinceActivity, "threshold =", thresholdMinutes) end

                -- Reset alert cycle when activity is recent
                if minutesSinceActivity < thresholdMinutes then
                    hasAlertedThisCycle = false
                    if HTM_DEBUG then print("[HTM Debug] Activity recent, resetting alert cycle") end
                    return
                end

                -- Check repeat setting
                local repeatEnabled = dmhub.GetSettingValue("herotokenmonitor:repeat")
                if HTM_DEBUG then print("[HTM Debug] repeatEnabled =", repeatEnabled, "hasAlertedThisCycle =", hasAlertedThisCycle) end

                -- If repeat is disabled and we've already alerted, skip
                if not repeatEnabled and hasAlertedThisCycle then
                    if HTM_DEBUG then print("[HTM Debug] Already alerted this cycle, repeat disabled") end
                    return
                end

                -- Check if enough time has passed since last alert (for repeat mode)
                local sinceAlertSeconds = dmhub.serverTime - lastAlertTime
                local sinceAlertMinutes = sinceAlertSeconds / 60
                if HTM_DEBUG then print("[HTM Debug] sinceAlertMinutes =", sinceAlertMinutes) end

                if sinceAlertMinutes < thresholdMinutes then
                    if HTM_DEBUG then print("[HTM Debug] Too soon since last alert") end
                    return
                end

                -- Send alert
                local displayMinutes = math.floor(minutesSinceActivity)
                if HTM_DEBUG then print("[HTM Debug] SENDING ALERT:", displayMinutes, "minutes") end
                chat.Send("[Hero Token Reminder] Heroes: remember to use your hero tokens! Director: remember to bestow hero tokens! (No hero tokens gained or used in " .. displayMinutes .. " minutes)")
                lastAlertTime = dmhub.serverTime
                hasAlertedThisCycle = true
            end,
        },
    }
end

-- Initialize on game entry
dmhub.RegisterEventHandler("EnterGame", function()
    -- Only initialize for the GM
    if not dmhub.isDM then
        return
    end

    dmhub.Coroutine(function()
        -- Wait for HUD to be ready (standard DMHub initialization pattern)
        while (not GameHud.instance) or
              (not GameHud.instance.dialogWorldPanel) or
              (not GameHud.instance.dialogWorldPanel.valid) do
            coroutine.yield()
        end

        -- Extra frames for safety
        for i = 1, 5 do
            coroutine.yield()
        end

        -- Attach the invisible checker panel
        GameHud.instance.dialogWorldPanel:AddChild(CreateInactivityChecker())

        if HTM_DEBUG then print("[HTM] Initialized") end
    end)
end)
