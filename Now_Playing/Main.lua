local mod = dmhub.GetModLoading()

setting{
  id = "nowplaying:solo_mode",
  description = "Play Only the Latest Sound",
  editor = "check",
  default = false,
  storage = "preference",
  section = "Now Playing",
}

local function CreateTrackRow(assetId, soundEvent, isSoloMuted)
  local audioAsset = assets.audioTable[assetId]
  if audioAsset == nil then
    return nil
  end

  local trackName = audioAsset.description or "Unknown"
  local isLooping = audioAsset.loop

  local loopIndicator = ""
  if isLooping and dmhub.isDM then
    loopIndicator = " [looped]"
  end

  local trackChildren = {}

  -- DM: stop button always on left
  if dmhub.isDM then
    local stopButton = gui.Panel{
      bgimage = "panels/square.png",
      bgcolor = "#aa3333",
      width = 14,
      height = 14,
      cornerRadius = 2,
      valign = "center",
      styles = {
        {
          selectors = {"hover"},
          bgcolor = "#dd4444",
        },
      },
      press = function(element)
        audio.StopSoundEvent(assetId)
      end,
    }

    trackChildren[#trackChildren + 1] = stopButton
    trackChildren[#trackChildren + 1] = gui.Panel{ width = 8, height = 1 }
  end

  -- Track name (with muted indicator if solo-muted)
  local displayName = trackName .. loopIndicator
  if isSoloMuted then
    displayName = displayName .. "  (muted)"
  end

  trackChildren[#trackChildren + 1] = gui.Label{
    text = displayName,
    fontSize = 14,
    bold = true,
    color = cond(isSoloMuted, "#888888", Styles.textColor),
    width = "auto",
    height = "auto",
    valign = "center",
  }

  -- DM: volume controls (only when not solo-muted)
  if dmhub.isDM and not isSoloMuted then
    local volumeSlider = gui.Slider{
      value = audioAsset.volume,
      minValue = 0,
      maxValue = 1,
      sliderWidth = 60,
      handleSize = "100%",
      labelWidth = 0,
      labelFormat = "",
      style = {
        width = 60,
        height = 16,
        valign = "center",
      },
      events = {
        preview = function(element)
          audio.PreviewSoundEventVolume(assetId, element.value)
        end,
        confirm = function(element)
          audio.SetSoundEventVolume(assetId, element.value)
        end,
      },
    }

    trackChildren[#trackChildren + 1] = gui.Panel{ width = 8, height = 1 }
    trackChildren[#trackChildren + 1] = gui.Panel{
      bgimage = "ui-icons/AudioVolumeButton.png",
      bgcolor = Styles.textColor,
      width = 12,
      height = 12,
      valign = "center",
    }
    trackChildren[#trackChildren + 1] = gui.Panel{ width = 4, height = 1 }
    trackChildren[#trackChildren + 1] = volumeSlider
  end

  local trackRow = gui.Panel{
    width = "100%",
    height = "auto",
    flow = "horizontal",
    vmargin = 8,
    hpad = 10,
    children = trackChildren,
  }

  return trackRow
end

local function CreateNowPlayingPanel()
  -- Shared document for syncing solo state to players
  local SOLO_DOC_ID = "nowplaying:solo"

  local function UpdateSoloDoc(trackId)
    local doc = mod:GetDocumentSnapshot(SOLO_DOC_ID)
    doc:BeginChange()
    doc.data.soloTrackId = trackId
    doc:CompleteChange("Update solo track")
  end

  -- Track order tracking for solo mode
  local trackOrder = {}   -- ordered list of asset IDs, newest last
  local savedVolumes = {} -- assetId -> volume before solo-muted

  local function GetSoloMode()
    return dmhub.GetSettingValue("nowplaying:solo_mode")
  end

  local function SetSoloMode(value)
    dmhub.SetSettingValue("nowplaying:solo_mode", value)
  end

  local function ApplySoloMode()
    if not GetSoloMode() or #trackOrder == 0 then return end
    local latestId = trackOrder[#trackOrder]
    for _, assetId in ipairs(trackOrder) do
      if assetId == latestId then
        local vol = savedVolumes[assetId] or 1
        audio.SetSoundEventVolume(assetId, vol)
      else
        audio.SetSoundEventVolume(assetId, 0)
      end
    end
    UpdateSoloDoc(latestId)
  end

  local function RestoreAllVolumes()
    for _, assetId in ipairs(trackOrder) do
      local vol = savedVolumes[assetId]
      if vol ~= nil then
        audio.SetSoundEventVolume(assetId, vol)
      end
    end
    savedVolumes = {}
    UpdateSoloDoc(nil)
  end

  local trackContainer = gui.Panel{
    width = "100%",
    height = "auto",
    flow = "vertical",
  }

  local emptyLabel = gui.Label{
    text = "Nothing playing",
    fontSize = 14,
    color = "#888888",
    width = "100%",
    height = 40,
    halign = "center",
    valign = "center",
    textAlignment = "center",
  }

  local lastTrackHash = ""
  local lastSoloTrackId = false  -- false = uninitialized, nil = no solo

  local function BuildTrackHash()
    local parts = {}
    for assetId, snd in pairs(audio.currentlyPlaying) do
      parts[#parts + 1] = assetId
    end
    table.sort(parts)
    return table.concat(parts, ",")
  end

  local function UpdateTrackOrder()
    -- Build set of currently playing IDs
    local currentSet = {}
    for assetId, _ in pairs(audio.currentlyPlaying) do
      currentSet[assetId] = true
    end

    -- Remove tracks that stopped
    local newOrder = {}
    for _, assetId in ipairs(trackOrder) do
      if currentSet[assetId] then
        newOrder[#newOrder + 1] = assetId
      else
        savedVolumes[assetId] = nil
      end
    end

    -- Detect new tracks (in currentlyPlaying but not in trackOrder)
    local existingSet = {}
    for _, assetId in ipairs(newOrder) do
      existingSet[assetId] = true
    end
    for assetId, soundEvent in pairs(audio.currentlyPlaying) do
      if not existingSet[assetId] then
        -- New track appeared
        if GetSoloMode() then
          -- Save the new track's volume before we potentially mute others
          local newAsset = assets.audioTable[assetId]
          savedVolumes[assetId] = newAsset and newAsset.volume or 1
          -- Mute the previously-latest track
          if #newOrder > 0 then
            local prevLatest = newOrder[#newOrder]
            if not savedVolumes[prevLatest] then
              local prevAsset = assets.audioTable[prevLatest]
              savedVolumes[prevLatest] = prevAsset and prevAsset.volume or 1
            end
          end
        end
        newOrder[#newOrder + 1] = assetId
      end
    end

    trackOrder = newOrder

    -- Apply solo logic if needed
    if GetSoloMode() and (#trackOrder > 0) then
      ApplySoloMode()
    end
  end

  local function RebuildTracks()
    local latestId = (#trackOrder > 0) and trackOrder[#trackOrder] or nil

    -- Non-DM clients: read solo state from shared document
    local soloTrackId = nil
    if not dmhub.isDM then
      local doc = mod:GetDocumentSnapshot(SOLO_DOC_ID)
      soloTrackId = doc.data.soloTrackId
    end

    local children = {}
    for assetId, soundEvent in pairs(audio.currentlyPlaying) do
      -- Players skip tracks that aren't the solo'd one
      if soloTrackId ~= nil and not dmhub.isDM and assetId ~= soloTrackId then
        -- skip: this track is muted by solo mode
      else
        local isSoloMuted = GetSoloMode() and (assetId ~= latestId)
        local row = CreateTrackRow(assetId, soundEvent, isSoloMuted)
        if row ~= nil then
          children[#children + 1] = row
        end
      end
    end
    trackContainer.children = children
  end

  -- Solo checkbox (DM only)
  local soloCheckbox = nil
  if dmhub.isDM then
    local soloIndicator = gui.Panel{
      bgimage = "panels/square.png",
      bgcolor = cond(GetSoloMode(), "#cccccc", "#555555"),
      width = 14,
      height = 14,
      cornerRadius = 2,
      valign = "center",
    }

    soloCheckbox = gui.Panel{
      width = "100%",
      height = "auto",
      flow = "horizontal",
      hpad = 8,
      vmargin = 4,
      styles = {
        {
          selectors = {"hover"},
          brightness = 1.3,
        },
      },
      press = function(element)
        SetSoloMode(not GetSoloMode())
        soloIndicator.selfStyle.bgcolor = cond(GetSoloMode(), "#cccccc", "#555555")
        if GetSoloMode() then
          -- Save current volumes and apply solo
          for _, assetId in ipairs(trackOrder) do
            local audioAsset = assets.audioTable[assetId]
            if audioAsset then
              savedVolumes[assetId] = audioAsset.volume
            end
          end
          ApplySoloMode()
        else
          RestoreAllVolumes()
        end
        RebuildTracks()
      end,
      children = {
        soloIndicator,
        gui.Panel{ width = 6, height = 1 },
        gui.Label{
          text = "Play Only the Latest Sound (Mute Others Until It Stops)",
          fontSize = 12,
          color = Styles.textColor,
          width = "auto",
          height = "auto",
          valign = "center",
        },
      },
    }
  end

  -- Master controls (DM only)
  local masterRow = nil
  local muteIcon = nil
  if dmhub.isDM then
    -- Separator line
    local separator = gui.Panel{
      width = "90%",
      height = 1,
      bgimage = "panels/square.png",
      bgcolor = "#555555",
      halign = "center",
      vmargin = 6,
    }

    -- Master volume controls
    local masterVolumeSlider = gui.Slider{
      value = cond(audio.muted, 0, audio.masterVolume),
      minValue = 0,
      maxValue = 1,
      sliderWidth = 70,
      handleSize = "100%",
      labelWidth = 0,
      labelFormat = "",
      style = {
        width = 70,
        height = 16,
        valign = "center",
      },
      events = {
        preview = function(element)
          audio.masterVolume = element.value
          if audio.masterVolume > 0 and audio.muted then
            audio.muted = false
            audio.UploadMuted()
          end
        end,
        confirm = function(element)
          audio.masterVolume = element.value
          if audio.masterVolume > 0 and audio.muted then
            audio.muted = false
            audio.UploadMuted()
          end
          audio.UploadMasterVolume()
        end,
        refreshAudio = function(element)
          element.value = cond(audio.muted, 0, audio.masterVolume)
        end,
      },
    }

    muteIcon = gui.Panel{
      bgimage = cond(audio.muted, "ui-icons/AudioMuteButton.png", "ui-icons/AudioVolumeButton.png"),
      bgcolor = Styles.textColor,
      width = 18,
      height = 18,
      valign = "center",
      styles = {
        {
          selectors = {"hover"},
          brightness = 2,
        },
      },
      press = function(element)
        audio.muted = not audio.muted
        audio.UploadMuted()
        muteIcon.bgimage = cond(audio.muted, "ui-icons/AudioMuteButton.png", "ui-icons/AudioVolumeButton.png")
      end,
    }

    local stopAllButton = gui.Panel{
      width = "auto",
      height = 24,
      halign = "center",
      hpad = 8,
      cornerRadius = 4,
      bgimage = "panels/square.png",
      bgcolor = "#aa3333",
      styles = {
        {
          selectors = {"hover"},
          bgcolor = "#dd4444",
        },
      },
      press = function(element)
        audio.StopAllSoundEvents()
      end,
      children = {
        gui.Label{
          text = "Stop All",
          fontSize = 12,
          bold = true,
          color = "white",
          width = "auto",
          height = "auto",
          halign = "center",
          valign = "center",
        },
      },
    }

    masterRow = gui.Panel{
      width = "100%",
      height = "auto",
      flow = "vertical",
      children = {
        separator,

        gui.Panel{
          width = "100%",
          height = "auto",
          flow = "horizontal",
          hpad = 8,
          children = {
            gui.Label{
              text = "Master Volume",
              fontSize = 12,
              bold = true,
              color = Styles.textColor,
              width = "auto",
              height = "auto",
              valign = "center",
            },
            gui.Panel{ width = 8, height = 1 },
            muteIcon,
            gui.Panel{ width = 4, height = 1 },
            masterVolumeSlider,
          },
        },

        gui.Panel{
          width = "100%",
          height = "auto",
          flow = "horizontal",
          hpad = 8,
          vmargin = 4,
          children = {
            stopAllButton,
          },
        },
      },
    }
  end

  -- Build main panel children
  local mainChildren = {}
  if soloCheckbox then
    mainChildren[#mainChildren + 1] = soloCheckbox
  end
  mainChildren[#mainChildren + 1] = emptyLabel
  mainChildren[#mainChildren + 1] = trackContainer
  if masterRow then
    mainChildren[#mainChildren + 1] = masterRow
  end

  local mainPanel = gui.Panel{
    width = "100%",
    height = "auto",
    flow = "vertical",
    vpad = 4,

    thinkTime = 0.5,
    think = function(element)
      local needsRebuild = false

      local currentHash = BuildTrackHash()
      if currentHash ~= lastTrackHash then
        lastTrackHash = currentHash
        if dmhub.isDM then
          UpdateTrackOrder()
        end
        needsRebuild = true
      end

      -- Player clients: check if solo state changed
      if not dmhub.isDM then
        local doc = mod:GetDocumentSnapshot(SOLO_DOC_ID)
        local soloTrackId = doc.data.soloTrackId
        if soloTrackId ~= lastSoloTrackId then
          lastSoloTrackId = soloTrackId
          needsRebuild = true
        end
      end

      if needsRebuild then
        RebuildTracks()
      end

      local hasPlaying = audio.numPlayingSounds > 0
      emptyLabel:SetClass("hidden", hasPlaying)
      trackContainer:SetClass("hidden", not hasPlaying)
      if masterRow then
        masterRow:SetClass("hidden", not hasPlaying)
      end
      if muteIcon then
        muteIcon.bgimage = cond(audio.muted, "ui-icons/AudioMuteButton.png", "ui-icons/AudioVolumeButton.png")
      end
    end,

    styles = {
      {
        selectors = {"hidden"},
        collapsed = 1,
      },
    },

    children = mainChildren,
  }

  audio.events:Listen(mainPanel)

  return mainPanel
end

DockablePanel.Register{
  name = "Now Playing",
  icon = "icons/standard/Icon_App_Audio.png",
  dmonly = false,
  vscroll = true,
  minHeight = 80,
  content = function()
    return CreateNowPlayingPanel()
  end,
}
