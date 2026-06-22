local mod = dmhub.GetModLoading()

setting{
    id = "tokenmasker:enabled",
    description = "Enable Token Masker (Requires Restart)",
    editor = "check",
    default = false,
    storage = "preference",
    section = "General",
    help = "When enabled, tokens matching the mask terms will be obscured. Restart client for changes to take effect on existing tokens.",
}

setting{
    id = "tokenmasker:terms",
    description = "Token Mask Terms",
    editor = "input",
    default = "",
    characterLimit = 500,
    storage = "preference",
    section = "General",
    help = "Comma-separated list of terms. Tokens whose names contain any of these terms will be masked. Case-insensitive. Restart client for changes to take effect.",
}

-- Helper function: Parse the comma-separated terms into a table
local function ParseMaskTerms()
    local termsString = dmhub.GetSettingValue("tokenmasker:terms") or ""
    local terms = {}

    for term in string.gmatch(termsString, "[^,]+") do
        -- Trim leading/trailing whitespace
        term = string.match(term, "^%s*(.-)%s*$")
        if term ~= nil and term ~= "" then
            -- Store lowercase for case-insensitive matching
            terms[#terms+1] = string.lower(term)
        end
    end

    return terms
end

-- Helper function: Check if a token name matches any mask term
local function ShouldMaskToken(token)
    -- Check if feature is enabled
    if not dmhub.GetSettingValue("tokenmasker:enabled") then
        return false
    end

    -- Get token name
    local tokenName = token.name
    if tokenName == nil or tokenName == "" then
        return false
    end

    -- Convert to lowercase for case-insensitive matching
    local lowerName = string.lower(tokenName)

    -- Parse and check against all mask terms
    local terms = ParseMaskTerms()
    for _, term in ipairs(terms) do
        if string.find(lowerName, term, 1, true) then
            return true
        end
    end

    return false
end

-- Store original portraits so we can restore them
local originalPortraits = {}

local MASK_IMAGE = "DEFAULT_MONSTER_AVATAR"

-- Apply or remove mask from a token
local function UpdateTokenMask(token)
    if token == nil or not token.valid then
        return
    end

    local shouldMask = ShouldMaskToken(token)
    local tokenId = token.charid

    if shouldMask then
        -- Save original portrait settings if we haven't already
        if originalPortraits[tokenId] == nil then
            originalPortraits[tokenId] = {
                portrait = token.portrait,
                brightness = token.portraitFrameBrightness,
            }
        end
        if token.portrait ~= MASK_IMAGE then
            token.portrait = MASK_IMAGE
            token:RefreshAppearanceLocally()
        end
    else
        if originalPortraits[tokenId] ~= nil then
            if token.portrait == MASK_IMAGE then
                token.portrait = originalPortraits[tokenId].portrait
                token.portraitFrameBrightness = originalPortraits[tokenId].brightness or 1
                token:RefreshAppearanceLocally()
            end
            originalPortraits[tokenId] = nil
        end
    end
end

-- Register a minimal panel just to trigger periodic updates
TokenHud.RegisterPanel{
    id = "tokenmasker:updater",
    ord = 100,

    create = function(token, sharedInfo)
        -- Initial mask check
        UpdateTokenMask(token)

        local updaterPanel = gui.Panel{
            interactable = false,
            blocksGameInteraction = false,
            floating = true,
            width = 1,
            height = 1,
            collapsed = true,  -- Invisible panel, just for updates

            thinkTime = 2,  -- Check every 2 seconds

            events = {
                think = function(element)
                    UpdateTokenMask(token)
                end,
            },
        }

        return updaterPanel
    end,
}

-- Force a rebuild of token UI to apply our new panel
dmhub.InvalidateTokenUI()
