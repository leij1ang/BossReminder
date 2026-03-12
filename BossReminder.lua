-- BossReminder: 主入口，状态 (spellEventMap / specID / activeProfile) + 专精切换 + 配置编排
local addonName = ... or "BossReminder"
local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")

local defaults = {
    profile = {
        settings = {
            brLogEnabled = false,
            countdownVoice = "",
            usePerSpec = false,
        },
        specConfigs = {},
    },
    global = { minimapIcon = {} },
}

local addon = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")
addon.defaults = defaults

addon.spellEventMap = {}
addon.specID = "default"
addon.activeProfile = nil

addon.db = AceDB:New("BossReminderDB", defaults, true)
addon.db.RegisterCallback(addon, "OnProfileChanged", function()
    addon:SyncActiveProfile()
    addon:ForceUpdateAllSounds()
end)

function addon:OnInitialize()
    self.L = LibStub("AceLocale-3.0"):GetLocale(self.name, true) or setmetatable({}, { __index = function(_, k) return k end })
    if self.ScanAllEvents then self:ScanAllEvents() end
end

function addon:OnEnable()
    self:SyncActiveProfile()
    self:ForceUpdateAllSounds()
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
end

function addon:OnSpecChanged()
    if not self:GetUsePerSpec() then return end
    self:ClearSound()
    self:SyncActiveProfile()
    self:SetSound()
    if self.UpdateOverview then self:UpdateOverview() end
end

function addon:SyncActiveProfile()
    self.specID = self:GetCurrentSpecKey()
    self.activeProfile = self:GetCurrentSpecSpellsTable()
end

function addon:AddSpellConfig(profileName, spellID, config)
    if not spellID or not config then return end
    self:SaveSpellConfigToProfile(profileName, spellID, config)
    if profileName ~= self:GetCurrentSpecKey() then return end
    self:ClearSoundBySpell(spellID)
    self:SetSoundBySpell(spellID, config)
end

function addon:RemoveSpellConfig(profileName, spellID)
    local id = tonumber(spellID)
    if not id then return end
    self:RemoveSpellConfigFromProfile(profileName, id)
    if profileName ~= self:GetCurrentSpecKey() then return end
    self:ClearSoundBySpell(id)
end

function addon:RemoveAllSpellConfigs(profileName)
    self:ClearSoundForProfile(profileName)
    self:RemoveAllSpellConfigsFromProfile(profileName)
end

_G.BossReminder = addon
