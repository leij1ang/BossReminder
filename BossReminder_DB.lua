-- BossReminder_DB: 专精/配置读写，specConfigs[].spells，不碰语音
local addon = _G.BossReminder
if not addon or not addon.db then return end

local brLog = addon.brLog

local function getSettings(p)
    if not p.settings or type(p.settings) ~= "table" then p.settings = {} end
    return p.settings
end

local function GetActiveSpecKey()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then return "default" end
    local idx = GetSpecialization()
    if not idx then return "default" end
    local specID = GetSpecializationInfo(idx)
    return specID and tostring(specID) or "default"
end

function addon:GetCurrentSpecKey()
    return getSettings(self.db.profile).usePerSpec and GetActiveSpecKey() or "default"
end

function addon:GetUsePerSpec()
    return getSettings(self.db.profile).usePerSpec == true
end

function addon:SetUsePerSpec(value)
    getSettings(self.db.profile).usePerSpec = value and true or false
end

function addon:SetCurrentSpecKey() end

local function deepCopySpells(src)
    if not src or type(src) ~= "table" then return {} end
    local dst = {}
    for spellID, cfg in pairs(src) do
        local c = {}
        for k, v in pairs(cfg) do c[k] = v end
        dst[spellID] = c
    end
    return dst
end

function addon:GetCurrentSpecSpellsTable()
    local p = self.db.profile
    p.specConfigs = p.specConfigs or {}
    local key = self:GetCurrentSpecKey()
    if key == "default" then
        local def = p.specConfigs["default"] or {}
        def.spells = def.spells or {}
        p.specConfigs["default"] = def
        return def.spells
    end
    local spec = p.specConfigs[key]
    if not spec or not spec.spells or next(spec.spells) == nil then
        local defSpells = (p.specConfigs["default"] and p.specConfigs["default"].spells) or {}
        spec = { spells = deepCopySpells(defSpells) }
        p.specConfigs[key] = spec
    end
    return spec.spells
end

function addon:GetCurrentSpecSpells()
    return self:GetCurrentSpecSpellsTable() or {}
end

function addon:EnsureSpecSpells(profileName)
    local p = self.db.profile
    p.specConfigs = p.specConfigs or {}
    local spec = p.specConfigs[profileName] or {}
    spec.spells = spec.spells or {}
    p.specConfigs[profileName] = spec
    return spec.spells
end

function addon:SaveSpellConfigToProfile(profileName, spellID, config)
    if not profileName or not spellID or not config then return end
    local spells = self:EnsureSpecSpells(profileName)
    spells[spellID] = config
end

function addon:RemoveSpellConfigFromProfile(profileName, spellID)
    if not profileName or not spellID then return end
    local spells = self:EnsureSpecSpells(profileName)
    spells[spellID] = nil
end

function addon:RemoveAllSpellConfigsFromProfile(profileName)
    if not profileName then return end
    local spells = self:EnsureSpecSpells(profileName)
    for k in pairs(spells) do spells[k] = nil end
end

function addon:GetSpellConfig(spellID, createIfMissing)
    if not spellID then return nil end
    local spells = self:GetCurrentSpecSpellsTable()
    if not spells then return nil end
    local cfg = spells[spellID]
    if not cfg and createIfMissing then
        cfg = { enabled = true, warningSound = "", highlightSound = "", shouldCountdown = false }
        spells[spellID] = cfg
    end
    if cfg and cfg.enabled == nil then cfg.enabled = true end
    return cfg, spellID
end

function addon:SetSpellEnabled(spellID, enabled)
    local cfg = self:GetSpellConfig(spellID, true)
    if not cfg then return end
    cfg.enabled = enabled
    self:AddSpellConfig(self:GetCurrentSpecKey(), spellID, cfg)
end

function addon:ScanAllEvents()
    local map = {}
    if C_EncounterEvents and C_EncounterEvents.GetEventList then
        local list = C_EncounterEvents.GetEventList()
        if type(list) == "table" then
            for _, eventID in ipairs(list) do
                if C_EncounterEvents.HasEventInfo and C_EncounterEvents.HasEventInfo(eventID) then
                    local info = C_EncounterEvents.GetEventInfo(eventID)
                    if info and info.spellID then map[info.spellID] = eventID end
                end
            end
        end
    end
    self.spellEventMap = map
    if brLog then brLog("ScanAllEvents: %d spells", (function() local n=0 for _ in pairs(map) do n=n+1 end return n end)()) end
    return map
end

function addon:GetEventIDBySpellID(spellID)
    return self.spellEventMap and self.spellEventMap[spellID]
end

function addon:SetCountdownVoice(value)
    getSettings(self.db.profile).countdownVoice = value and value ~= "" and value or ""
    self:ForceUpdateAllSounds()
end

function addon:SetBrLogEnabled(value)
    getSettings(self.db.profile).brLogEnabled = value and true or false
end
