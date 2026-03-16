-- BossReminder_Sound: 按 spell 设置/清除语音，仅函数调用
local addon = _G.BossReminder
if not addon then return end

local EncounterEventSoundTrigger = Enum.EncounterEventSoundTrigger
local TRIGGER_WARNING = EncounterEventSoundTrigger.OnTimelineEventFinished
local TRIGGER_HIGHLIGHT = EncounterEventSoundTrigger.OnTimelineEventHighlight
local TRIGGER_TEXT = EncounterEventSoundTrigger.OnTextWarningShown
local GetSelectedSoundPath = addon.GetSelectedSoundPath
local brLog = addon.brLog

local function SetSoundsByEventID(eventID, triggerEnum, sound)
    brLog("SetSoundsByEventID eventID=%s, triggerEnum=%s, sound=%s", tostring(eventID), tostring(triggerEnum), tostring(sound))
    if not eventID then return end
    if sound ~= nil then
        if type(sound) ~= "table" or not sound.file then return end
        local ok, err = pcall(C_EncounterEvents.SetEventSound, eventID, triggerEnum, sound)
        if not ok and brLog then brLog("SetEventSound failed eventID=%s", tostring(err)) end
        return
    end
    if triggerEnum then
        pcall(C_EncounterEvents.SetEventSound, eventID, triggerEnum, nil)
    else
        pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_WARNING, nil)
        pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_HIGHLIGHT, nil)
        pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_TEXT, nil)
    end
end

function addon:SetSoundBySpell(spellID, config)
    if not spellID or not config or config.enabled == false then return end
    local eventID = self:GetEventIDBySpellID(spellID)
    if not eventID then return end
    if config.warningSound and config.warningSound ~= "" then
        local path = GetSelectedSoundPath and GetSelectedSoundPath(config.warningSound)
        if path and path ~= "" then
            SetSoundsByEventID(eventID, TRIGGER_WARNING, { file = path, channel = "Master", volume = 1 })
        end
    end
    local path = (config.highlightSound and config.highlightSound ~= "") and (GetSelectedSoundPath and GetSelectedSoundPath(config.highlightSound))
    if path and path ~= "" then
        SetSoundsByEventID(eventID, TRIGGER_HIGHLIGHT, { file = path, channel = "Master", volume = 1 })
    end
    path = (config.textSound and config.textSound ~= "") and (GetSelectedSoundPath and GetSelectedSoundPath(config.textSound))
    if path and path ~= "" then
        SetSoundsByEventID(eventID, TRIGGER_TEXT, { file = path, channel = "Master", volume = 1 })
    end
end

function addon:ClearSoundBySpell(spellID)
    if not spellID then return end
    local eventID = self:GetEventIDBySpellID(spellID)
    if eventID then SetSoundsByEventID(eventID, nil, nil) end
end

local TRIGGER_KEY_MAP = {
    warningSound = TRIGGER_WARNING,
    highlightSound = TRIGGER_HIGHLIGHT,
    textSound = TRIGGER_TEXT,
}

function addon:SetSoundBySpellTrigger(spellID, triggerKey, value)
    if not spellID or not triggerKey then return end
    local eventID = self:GetEventIDBySpellID(spellID)
    if not eventID then return end
    local triggerEnum = TRIGGER_KEY_MAP[triggerKey]
    if not triggerEnum then return end
    if value and value ~= "" then
        local path = GetSelectedSoundPath and GetSelectedSoundPath(value)
        if path and path ~= "" then
            SetSoundsByEventID(eventID, triggerEnum, { file = path, channel = "Master", volume = 1 })
        end
    else
        SetSoundsByEventID(eventID, triggerEnum, nil)
    end
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

function addon:ForceUpdateAllSounds()
    self:ClearSound()
    self:SetSound()
end
