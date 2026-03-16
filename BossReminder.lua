-- BossReminder: 主入口，状态 (spellEventMap / specID / activeProfile) + 专精切换 + 配置编排
local addonName = ... or "BossReminder"

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

local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")
_G.BossReminder = addon

addon.spellEventMap = {}
addon.specID = "default"
addon.activeProfile = nil


function addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("BossReminderDB", defaults, true)
    self.L = LibStub("AceLocale-3.0"):GetLocale(self.name, true)
    if self.ScanAllEvents then self:ScanAllEvents() end

    -- LibDBIcon
    local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("BossReminder", {
        type = "launcher", icon = "Interface\\AddOns\\BossReminder\\BossReminder.tga",
        OnClick = function(_, button) if button == "LeftButton" then local fn = addon.OpenUI or addon.OpenConfig if fn then fn() end end end,
        OnTooltipShow = function(tt) tt:AddLine("BossReminder") tt:AddLine(self.L.TOOLTIP_MINIMAP_HINT or "Click to toggle Overview", 0.8, 0.8, 0.8) end,
    })
    if not addon.db.global.minimapIcon then addon.db.global.minimapIcon = {} end
    LibStub("LibDBIcon-1.0"):Register("BossReminder", ldb, addon.db.global.minimapIcon)
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
