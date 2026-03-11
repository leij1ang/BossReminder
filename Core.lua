local addonName, ns = ...

BossReminderDB = BossReminderDB or {}

ns.defaults = {
    enabled = true,
    timelineLogs = false,
    countdownVoice = "",
    spells = {},
}

-- Use version from Utils
local TimelineLog = ns.TimelineLog
local GetSelectedSoundPath = ns.GetSelectedSoundPath

local TRIGGER_WARNING = Enum and Enum.EncounterEventSoundTrigger and Enum.EncounterEventSoundTrigger.OnTimelineEventFinished
local TRIGGER_HIGHLIGHT = Enum and Enum.EncounterEventSoundTrigger and Enum.EncounterEventSoundTrigger.OnTimelineEventHighlight

local function CopyDefaults(src, dst)
    if type(src) ~= "table" then
        return dst
    end

    if type(dst) ~= "table" then
        dst = {}
    end

    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end

    return dst
end

-- Apply sound to system (eventID, trigger, sound object parameters match SetEventSound)
local function ApplySounds(eventID, triggerEnum, sound)
    if not eventID or not C_EncounterEvents or not C_EncounterEvents.SetEventSound then
        TimelineLog("ApplySounds: missing C_EncounterEvents or invalid eventID=%s", tostring(eventID))
        return
    end

    if not sound or type(sound) ~= "table" or not sound.file then
        TimelineLog("ApplySounds: sound is nil for eventID=%d", eventID)
        return
    end

    local ok, err = pcall(C_EncounterEvents.SetEventSound, eventID, triggerEnum, sound)
    if not ok then
        TimelineLog("ApplySounds: failed for eventID=%d, error=%s", eventID, tostring(err))
    end
end

-- Apply sound config for specified spell
local function ApplySoundConfig(spellID)
    if not spellID then
        return
    end

    ns.ClearSounds(spellID)

    local cfg = ns.runtimeDB:getSpellConfig(spellID)
    if not cfg or cfg.enabled == false then
        return
    end

    local eventID = ns.runtimeDB:getEventIDBySpellID(spellID)
    if not eventID then
        TimelineLog("ApplySoundConfig: no eventID found for spellID=%d", spellID)
        return
    end

    local warningPath = GetSelectedSoundPath(cfg.warningSound)
    local highlightKey = (cfg.shouldCountdown and BossReminderDB and BossReminderDB.countdownVoice) or cfg.highlightSound
    local highlightPath = GetSelectedSoundPath(highlightKey)
    local hasRegistered = false

    if warningPath and warningPath ~= "" and TRIGGER_WARNING then
        local warningInfo = {
            file = warningPath,
            channel = "Master",
            volume = 1,
        }
        TimelineLog("ApplySoundConfig: register warning sound spellID=%d eventID=%d", spellID, eventID)
        ApplySounds(eventID, TRIGGER_WARNING, warningInfo)
        hasRegistered = true
    end

    if highlightPath and highlightPath ~= "" and TRIGGER_HIGHLIGHT then
        local highlightInfo = {
            file = highlightPath,
            channel = "Master",
            volume = 1,
        }
        local sourceLabel = cfg.shouldCountdown and "countdownVoice" or "highlightSound"
        TimelineLog("ApplySoundConfig: register highlight sound(%s) spellID=%d eventID=%d", sourceLabel, spellID, eventID)
        ApplySounds(eventID, TRIGGER_HIGHLIGHT, highlightInfo)
        hasRegistered = true
    end

    if not hasRegistered then
        TimelineLog("ApplySoundConfig: no sound path for spellID=%d", spellID)
    end
end

-- Scan all events and build spellID -> eventID mapping, stored in cache
local function ScanAllEvents()
    local map = {}
    if not C_EncounterEvents or not C_EncounterEvents.GetEventList then
        ns.runtimeDB:setSpellEventMap(map)
        return map
    end

    local eventList = C_EncounterEvents.GetEventList()
    if not eventList or type(eventList) ~= "table" then
        ns.runtimeDB:setSpellEventMap(map)
        return map
    end

    for _, eventID in ipairs(eventList) do
        if C_EncounterEvents.HasEventInfo and C_EncounterEvents.HasEventInfo(eventID) then
            local eventInfo = C_EncounterEvents.GetEventInfo(eventID)
            if eventInfo and eventInfo.spellID then
                map[eventInfo.spellID] = eventID
            end
        end
    end

    ns.runtimeDB:setSpellEventMap(map)
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    TimelineLog("ScanAllEvents: mapped %d spells to events", count)
    return map
end

-- Clear sound settings for specified spellID
local function ClearSounds(spellID)
    if not spellID or not ns.runtimeDB then
        return
    end

    local eventID = ns.runtimeDB:getEventIDBySpellID(spellID)
    if not eventID or not C_EncounterEvents or not C_EncounterEvents.SetEventSound then
        return
    end

    local cleared = false

    if TRIGGER_WARNING then
        local ok, err = pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_WARNING, nil)
        if not ok then
            TimelineLog("ClearSounds: failed to clear warning sound for spellID=%d eventID=%d, error=%s", spellID, eventID, tostring(err))
        else
            cleared = true
        end
    end

    if TRIGGER_HIGHLIGHT then
        local ok, err = pcall(C_EncounterEvents.SetEventSound, eventID, TRIGGER_HIGHLIGHT, nil)
        if not ok then
            TimelineLog("ClearSounds: failed to clear highlight sound for spellID=%d eventID=%d, error=%s", spellID, eventID, tostring(err))
        else
            cleared = true
        end
    end

    if cleared then
        TimelineLog("ClearSounds: cleared sounds for spellID=%d eventID=%d", spellID, eventID)
    end
end

-- Apply all enabled spell sound configs
local function ApplyAllSpellSounds()
    local spellEventMap = ns.runtimeDB:getSpellEventMap()
    local spellConfigs = ns.runtimeDB:getAllSpellConfigs()
    local count = 0

    local configCount = 0
    for _ in pairs(spellConfigs) do configCount = configCount + 1 end
    TimelineLog("ApplyAllSpellSounds: starting, total configs=%d", configCount)

    for spellID, cfg in pairs(spellConfigs) do
        if cfg and cfg.enabled ~= false then
            local eventID = spellEventMap[spellID]
            if eventID then
                local warningPath = GetSelectedSoundPath(cfg.warningSound)
                local highlightKey = (cfg.shouldCountdown and BossReminderDB and BossReminderDB.countdownVoice) or cfg.highlightSound
                local highlightPath = GetSelectedSoundPath(highlightKey)

                if warningPath and warningPath ~= "" and TRIGGER_WARNING then
                    local warningInfo = {
                        file = warningPath,
                        channel = "Master",
                    }
                    TimelineLog("ApplyAllSpellSounds: register warning sound spellID=%d eventID=%d", spellID, eventID)
                    ApplySounds(eventID, TRIGGER_WARNING, warningInfo)
                    count = count + 1
                end

                if highlightPath and highlightPath ~= "" and TRIGGER_HIGHLIGHT then
                    local highlightInfo = {
                        file = highlightPath,
                        channel = "Master",
                    }
                    local sourceLabel = cfg.shouldCountdown and "countdownVoice" or "highlightSound"
                    TimelineLog("ApplyAllSpellSounds: register highlight sound(%s) spellID=%d eventID=%d", sourceLabel, spellID, eventID)
                    ApplySounds(eventID, TRIGGER_HIGHLIGHT, highlightInfo)
                    count = count + 1
                end
            end
        end
    end
    TimelineLog("ApplyAllSpellSounds: processed %d spells with sounds", count)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")


frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            return
        end
        BossReminderDB = CopyDefaults(ns.defaults, BossReminderDB)
        -- Cache persistent data to runtime
        ns.runtimeDB:cacheSpells(BossReminderDB.spells)
        ScanAllEvents()
        return
    elseif event == "PLAYER_LOGIN" then
        -- Apply sounds after all addons loaded, ensure LSM sounds already registered
        ApplyAllSpellSounds()
        return
    end
end)

ns.ApplySoundConfig = ApplySoundConfig
ns.ClearSounds = ClearSounds
