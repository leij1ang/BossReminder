-- BossReminder_Sound: 按 spell 设置/清除语音，仅函数调用
local addon = _G.BossReminder
if not addon or not addon.db then return end

local TRIGGER_WARNING = Enum and Enum.EncounterEventSoundTrigger and Enum.EncounterEventSoundTrigger.OnTimelineEventFinished
local TRIGGER_HIGHLIGHT = Enum and Enum.EncounterEventSoundTrigger and Enum.EncounterEventSoundTrigger.OnTimelineEventHighlight
local GetSelectedSoundPath = addon.GetSelectedSoundPath
local brLog = addon.brLog

local function SetSoundsByEventID(eventID, triggerEnum, sound)
    if not eventID or not C_EncounterEvents or not C_EncounterEvents.SetEventSound then return end
    if sound ~= nil then
        if type(sound) ~= "table" or not sound.file then return end
        local ok, err = pcall(C_EncounterEvents.SetEventSound, eventID, triggerEnum, sound)
        if not ok and brLog then brLog("SetEventSound failed eventID=%s", tostring(err)) end
        return
    end
    if triggerEnum then
        pcall(C_EncounterEvents.SetEventSound, eventID, triggerEnum, nil)
    else
        if TRIGGER_WARNING then pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_WARNING, nil) end
        if TRIGGER_HIGHLIGHT then pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_HIGHLIGHT, nil) end
    end
end

function addon:SetSoundBySpell(spellID, config)
    if not spellID or not config or config.enabled == false then return end
    local eventID = self:GetEventIDBySpellID(spellID)
    if not eventID then return end
    if config.warningSound and config.warningSound ~= "" then
        local path = GetSelectedSoundPath and GetSelectedSoundPath(config.warningSound)
        if path and path ~= "" and TRIGGER_WARNING then
            SetSoundsByEventID(eventID, TRIGGER_WARNING, { file = path, channel = "Master", volume = 1 })
        end
    end
    if TRIGGER_HIGHLIGHT then
        local path
        if config.highlightSound and config.highlightSound ~= "" then
            path = GetSelectedSoundPath and GetSelectedSoundPath(config.highlightSound)
        elseif config.shouldCountdown then
            local s = self.db.profile.settings
            if s and (s.countdownVoice or "") ~= "" then
                path = GetSelectedSoundPath and GetSelectedSoundPath(s.countdownVoice)
            end
        end
        if path and path ~= "" then
            SetSoundsByEventID(eventID, TRIGGER_HIGHLIGHT, { file = path, channel = "Master", volume = 1 })
        end
    end
end

function addon:ClearSoundBySpell(spellID)
    if not spellID then return end
    local eventID = self:GetEventIDBySpellID(spellID)
    if eventID then SetSoundsByEventID(eventID, nil, nil) end
end

function addon:SetSound()
    local profile = self.activeProfile
    if not profile or type(profile) ~= "table" then return end
    for spellID, config in pairs(profile) do
        self:SetSoundBySpell(spellID, config)
    end
end

function addon:ClearSound()
    local profile = self.activeProfile
    if not profile or type(profile) ~= "table" then return end
    for spellID in pairs(profile) do
        self:ClearSoundBySpell(spellID)
    end
end

function addon:ClearSoundForProfile(profileName)
    if not profileName then return end
    local p = self.db.profile
    local spec = p.specConfigs and p.specConfigs[profileName]
    local spells = spec and spec.spells
    if not spells then return end
    for spellID in pairs(spells) do
        self:ClearSoundBySpell(spellID)
    end
end

function addon:ForceUpdateAllSounds()
    self:ClearSound()
    self:SetSound()
end
