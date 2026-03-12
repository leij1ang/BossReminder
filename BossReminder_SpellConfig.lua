-- BossReminder_SpellConfig: single-spell config window + Encounter Journal (C) button
local addon = _G.BossReminder
if not addon or not addon.db then return end

local L = addon.L or setmetatable({}, { __index = function(_, k) return k end })
local AceGUI = LibStub("AceGUI-3.0")
local GetLSM = addon.GetLSM

local panel = { currentSpellID = nil, currentEncounterContext = nil }
local configWindow, soundDropdown, highlightSoundDropdown, countdownCheck, statusLabel
local highlightWarnLabel, countdownWarnLabel, highlightWarnSpace1, highlightWarnSpace2, countdownWarnSpace1, countdownWarnSpace2, enableToggleButton
local SOUND_NONE_KEY = "__none__"

_G.BossReminderConfigPanel = panel

local function BuildCurrentSpellStatusText(spellName, spellID, enabled)
    local text = string.format(L.STATUS_CURRENT_SPELL_FMT, spellName, spellID)
    if enabled == false then text = text .. " " .. (L.STATUS_DISABLED_TAG or "[Disabled]") end
    return text
end
local function GetToggleButtonText(enabled) return enabled == false and L.BUTTON_ENABLE or L.BUTTON_DISABLE end
local function HasSelectedSoundValue(value) return value ~= nil and value ~= "" and value ~= SOUND_NONE_KEY and value ~= L.NONE end
local function IsChecked(value) return value == true or value == 1 or value == "1" end

local function UpdateWarningVisibility()
    local hasHighlight = highlightSoundDropdown and HasSelectedSoundValue(highlightSoundDropdown:GetValue())
    local hasCountdown = countdownCheck and IsChecked(countdownCheck:GetValue())
    if highlightWarnLabel then if hasHighlight then highlightWarnLabel:SetText("|cffff0000" .. L.HIGHLIGHT_SOUND_WARN .. "|r") highlightWarnLabel.frame:Show() if highlightWarnSpace1 then highlightWarnSpace1.frame:Show() end if highlightWarnSpace2 then highlightWarnSpace2.frame:Show() end else highlightWarnLabel:SetText("") highlightWarnLabel.frame:Hide() if highlightWarnSpace1 then highlightWarnSpace1.frame:Hide() end if highlightWarnSpace2 then highlightWarnSpace2.frame:Hide() end end end
    if countdownWarnLabel then if hasCountdown then countdownWarnLabel:SetText("|cffff0000" .. L.COUNTDOWN_UNAVAILABLE .. "|r") countdownWarnLabel.frame:Show() if countdownWarnSpace1 then countdownWarnSpace1.frame:Show() end if countdownWarnSpace2 then countdownWarnSpace2.frame:Show() end else countdownWarnLabel:SetText("") countdownWarnLabel.frame:Hide() if countdownWarnSpace1 then countdownWarnSpace1.frame:Hide() end if countdownWarnSpace2 then countdownWarnSpace2.frame:Hide() end end end
end

function panel:IsShown() return configWindow and configWindow.frame and configWindow.frame:IsShown() or false end
function panel:Hide() if configWindow and configWindow.frame then configWindow.frame:Hide() end end
function panel:Raise() if configWindow and configWindow.frame then configWindow.frame:Raise() end end

local function InitSoundDropdown(dropdown, selected)
    if not dropdown then return end
    local list = { [SOUND_NONE_KEY] = L.NONE }
    local lsm = GetLSM and GetLSM()
    if lsm then
        local sounds = lsm:List("sound") or {}
        table.sort(sounds, function(a, b) return tostring(a) < tostring(b) end)
        for _, displayName in ipairs(sounds) do
            local plainName = displayName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            list[plainName] = displayName
            if displayName ~= plainName then list[displayName] = displayName end
        end
    end
    dropdown:SetList(list)
    if selected and selected ~= "" then
        if list[selected] then dropdown:SetValue(selected)
        else local plainSelected = selected:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") dropdown:SetValue(list[plainSelected] and plainSelected or SOUND_NONE_KEY) end
    else dropdown:SetValue(SOUND_NONE_KEY) end
end

local function BuildConfigWindow()
    if configWindow then return end
    configWindow = AceGUI:Create("Window") configWindow:SetTitle(L.TITLE) configWindow:SetWidth(500) configWindow:SetHeight(360) configWindow:SetLayout("List") configWindow.frame:SetAlpha(0.9) configWindow:SetCallback("OnClose", function(w) w.frame:Hide() end)
    local body = AceGUI:Create("SimpleGroup") body:SetLayout("List") body:SetFullWidth(true) body:SetFullHeight(true) configWindow:AddChild(body)
    local soundLabel = AceGUI:Create("Label") soundLabel:SetText(L.SHARED_MEDIA) soundLabel:SetFullWidth(true) body:AddChild(soundLabel)
    local soundRow = AceGUI:Create("SimpleGroup") soundRow:SetLayout("Flow") soundRow:SetFullWidth(true)
    soundDropdown = AceGUI:Create("Dropdown") soundDropdown:SetLabel("") soundDropdown:SetWidth(260) soundDropdown:SetCallback("OnValueChanged", function(_, _, value) if value == SOUND_NONE_KEY then if panel.currentSpellID then SaveCurrentSpell() end return end local lsm = GetLSM() if lsm then local path = lsm:Fetch("sound", value, true) if path and path ~= "" then PlaySoundFile(path, "Master") end end if panel.currentSpellID then SaveCurrentSpell() end end) soundRow:AddChild(soundDropdown)
    local soundPreviewButton = AceGUI:Create("Button") soundPreviewButton:SetText(L.BUTTON_PREVIEW) soundPreviewButton:SetAutoWidth(true) soundPreviewButton:SetCallback("OnClick", function() local v = soundDropdown:GetValue() if v and v ~= SOUND_NONE_KEY and GetLSM then local path = GetLSM():Fetch("sound", v, true) if path and path ~= "" then PlaySoundFile(path, "Master") end end end) soundRow:AddChild(soundPreviewButton) body:AddChild(soundRow)
    local highlightRow = AceGUI:Create("SimpleGroup") local highlightSoundLabel = AceGUI:Create("Label") highlightSoundLabel:SetText(L.HIGHLIGHT_SOUND) highlightSoundLabel:SetFullWidth(true) highlightRow:AddChild(highlightSoundLabel) highlightRow:SetLayout("Flow") highlightRow:SetFullWidth(true)
    highlightSoundDropdown = AceGUI:Create("Dropdown") highlightSoundDropdown:SetLabel("") highlightSoundDropdown:SetWidth(260) highlightSoundDropdown:SetCallback("OnValueChanged", function(_, _, value) if HasSelectedSoundValue(value) and countdownCheck and IsChecked(countdownCheck:GetValue()) then countdownCheck:SetValue(false) end UpdateWarningVisibility() if HasSelectedSoundValue(value) and GetLSM then local path = GetLSM():Fetch("sound", value, true) if path and path ~= "" then PlaySoundFile(path, "Master") end end if panel.currentSpellID then SaveCurrentSpell() end end) highlightRow:AddChild(highlightSoundDropdown)
    local highlightPreviewButton = AceGUI:Create("Button") highlightPreviewButton:SetText(L.BUTTON_PREVIEW) highlightPreviewButton:SetAutoWidth(true) highlightPreviewButton:SetCallback("OnClick", function() if HasSelectedSoundValue(highlightSoundDropdown and highlightSoundDropdown:GetValue()) and GetLSM then local path = GetLSM():Fetch("sound", highlightSoundDropdown:GetValue(), true) if path and path ~= "" then PlaySoundFile(path, "Master") end end end) highlightRow:AddChild(highlightPreviewButton) body:AddChild(highlightRow)
    highlightWarnSpace1 = AceGUI:Create("Label") highlightWarnSpace1:SetText("") highlightWarnSpace1:SetFullWidth(true) highlightWarnSpace1.frame:Hide() body:AddChild(highlightWarnSpace1) highlightWarnLabel = AceGUI:Create("Label") highlightWarnLabel:SetText("") highlightWarnLabel:SetFullWidth(true) highlightWarnLabel.frame:Hide() body:AddChild(highlightWarnLabel) highlightWarnSpace2 = AceGUI:Create("Label") highlightWarnSpace2:SetText("") highlightWarnSpace2:SetFullWidth(true) highlightWarnSpace2.frame:Hide() body:AddChild(highlightWarnSpace2)
    countdownCheck = AceGUI:Create("CheckBox") countdownCheck:SetLabel(L.COUNTDOWN_5S) countdownCheck:SetValue(false) countdownCheck:SetFullWidth(true) countdownCheck:SetCallback("OnValueChanged", function(_, _, value) if IsChecked(value) and highlightSoundDropdown and HasSelectedSoundValue(highlightSoundDropdown:GetValue()) then highlightSoundDropdown:SetValue(SOUND_NONE_KEY) end UpdateWarningVisibility() if panel.currentSpellID then SaveCurrentSpell() end end) body:AddChild(countdownCheck)
    countdownWarnSpace1 = AceGUI:Create("Label") countdownWarnSpace1:SetText("") countdownWarnSpace1:SetFullWidth(true) countdownWarnSpace1.frame:Hide() body:AddChild(countdownWarnSpace1) countdownWarnLabel = AceGUI:Create("Label") countdownWarnLabel:SetText("") countdownWarnLabel:SetFullWidth(true) countdownWarnLabel.frame:Hide() body:AddChild(countdownWarnLabel) countdownWarnSpace2 = AceGUI:Create("Label") countdownWarnSpace2:SetText("") countdownWarnSpace2:SetFullWidth(true) countdownWarnSpace2.frame:Hide() body:AddChild(countdownWarnSpace2)
    statusLabel = AceGUI:Create("Label") statusLabel:SetText(L.STATUS_OPEN_FROM_EJ) statusLabel:SetFullWidth(true) body:AddChild(statusLabel)
    local buttonRow = AceGUI:Create("SimpleGroup") buttonRow:SetLayout("Flow") buttonRow:SetFullWidth(true) body:AddChild(buttonRow)
    local overviewButton = AceGUI:Create("Button") overviewButton:SetText(L.BUTTON_OVERVIEW) overviewButton:SetWidth(100) overviewButton:SetCallback("OnClick", function() addon.OpenOverview() end) buttonRow:AddChild(overviewButton)
    enableToggleButton = AceGUI:Create("Button") enableToggleButton:SetText(L.BUTTON_DISABLE) enableToggleButton:SetAutoWidth(true) enableToggleButton:SetCallback("OnClick", function() local id = panel.currentSpellID if not id then statusLabel:SetText(L.STATUS_SAVE_NEED_SELECT) return end local cfg = addon:GetSpellConfig(id, true) if not cfg then statusLabel:SetText(L.STATUS_SAVE_INVALID) return end addon:SetSpellEnabled(id, cfg.enabled == false) local newCfg = addon:GetSpellConfig(id) local spellName = C_Spell and C_Spell.GetSpellName(id) or L.SPELL_UNKNOWN statusLabel:SetText(BuildCurrentSpellStatusText(spellName, id, newCfg and newCfg.enabled)) enableToggleButton:SetText(GetToggleButtonText(newCfg and newCfg.enabled)) if addon.RefreshOverviewData then addon.RefreshOverviewData() end end) buttonRow:AddChild(enableToggleButton)
end

local function GetCurrentEncounterContext()
    if type(EJ_GetEncounterInfo) ~= "function" then return nil end
    local encounterID if EncounterJournal then encounterID = tonumber(EncounterJournal.encounterID) if not encounterID and type(EncounterJournal.encounter) == "table" then encounterID = tonumber(EncounterJournal.encounter.encounterID) if not encounterID and type(EncounterJournal.encounter.info) == "table" then encounterID = tonumber(EncounterJournal.encounter.info.encounterID) end end end
    if not encounterID and EncounterJournalEncounterFrameInfo then encounterID = tonumber(EncounterJournalEncounterFrameInfo.encounterID) end
    if not encounterID then return nil end
    local _, _, _, _, _, journalInstanceID, dungeonEncounterID, instanceID = EJ_GetEncounterInfo(encounterID)
    return { encounterID = encounterID, bossID = encounterID, dungeonEncounterID = dungeonEncounterID, instanceID = instanceID, journalInstanceID = journalInstanceID }
end

function SaveCurrentSpell()
    BuildConfigWindow() local id = panel.currentSpellID if not id then statusLabel:SetText(L.STATUS_SAVE_NEED_SELECT) return end
    local cfg = addon:GetSpellConfig(id, true) if not cfg then statusLabel:SetText(L.STATUS_SAVE_INVALID) return end
    local selectedSound = soundDropdown and soundDropdown:GetValue() or SOUND_NONE_KEY cfg.warningSound = (selectedSound and selectedSound ~= SOUND_NONE_KEY) and selectedSound or ""
    local selectedHighlight = highlightSoundDropdown and highlightSoundDropdown:GetValue() or SOUND_NONE_KEY cfg.highlightSound = (selectedHighlight and selectedHighlight ~= SOUND_NONE_KEY) and selectedHighlight or ""
    if cfg.highlightSound ~= "" then cfg.shouldCountdown = false countdownCheck:SetValue(false) elseif IsChecked(countdownCheck:GetValue()) then cfg.shouldCountdown = true cfg.highlightSound = "" if highlightSoundDropdown then highlightSoundDropdown:SetValue(SOUND_NONE_KEY) end else cfg.shouldCountdown = false end
    local encounterContext = panel.currentEncounterContext or GetCurrentEncounterContext() cfg.spellID = id cfg.bossID = (encounterContext and encounterContext.bossID) or cfg.bossID cfg.dungeonEncounterID = (encounterContext and encounterContext.dungeonEncounterID) or cfg.dungeonEncounterID cfg.instanceID = (encounterContext and encounterContext.instanceID) or cfg.instanceID cfg.journalInstanceID = (encounterContext and encounterContext.journalInstanceID) or cfg.journalInstanceID cfg.encounterID = (encounterContext and encounterContext.encounterID) or cfg.encounterID
    statusLabel:SetText(string.format(L.STATUS_SAVED_FMT, C_Spell and C_Spell.GetSpellName(id) or L.SPELL_UNKNOWN, id))
    addon:AddSpellConfig(addon:GetCurrentSpecKey(), id, cfg)
    if addon.RefreshOverviewData then addon.RefreshOverviewData() end
end

local function LoadSpell(spellID)
    BuildConfigWindow() local cfg, normalized = addon:GetSpellConfig(spellID, true) if not cfg then statusLabel:SetText(L.STATUS_INVALID_SPELL_ID) panel.currentSpellID = nil return end
    panel.currentSpellID = normalized countdownCheck:SetValue(cfg.shouldCountdown and true or false) InitSoundDropdown(soundDropdown, cfg.warningSound) InitSoundDropdown(highlightSoundDropdown, cfg.highlightSound) if cfg.highlightSound and cfg.highlightSound ~= "" then countdownCheck:SetValue(false) elseif cfg.shouldCountdown and highlightSoundDropdown then highlightSoundDropdown:SetValue(SOUND_NONE_KEY) end UpdateWarningVisibility() statusLabel:SetText(BuildCurrentSpellStatusText(C_Spell and C_Spell.GetSpellName(normalized) or L.SPELL_UNKNOWN, normalized, cfg.enabled)) if enableToggleButton then enableToggleButton:SetText(GetToggleButtonText(cfg.enabled)) end
end

function addon.OpenConfig(spellID)
    BuildConfigWindow() panel:Raise() panel.currentEncounterContext = GetCurrentEncounterContext()
    configWindow.frame:Show() LoadSpell(spellID)
end

-- Encounter Journal hook
local function EnsureConfigButton(hostFrame, spellID) if not hostFrame or not spellID then return end if hostFrame.BRPConfigButton then hostFrame.BRPConfigButton.spellID = spellID hostFrame.BRPConfigButton:Show() return end
    local b = CreateFrame("Button", nil, hostFrame, "UIPanelButtonTemplate") b:SetSize(20, 18) b:SetPoint("RIGHT", hostFrame, "RIGHT", -22, 0) b:SetText("C") b.spellID = spellID b:SetScript("OnClick", function(self) local id = tonumber(self.spellID) if id then addon.OpenConfig(id) end end) b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(L.TOOLTIP_CONFIG_SPELL, 1, 1, 1) if self.spellID then GameTooltip:AddLine(string.format(L.TOOLTIP_SPELL_ID_FMT, self.spellID), 0.8, 0.8, 0.8) end GameTooltip:Show() end) b:SetScript("OnLeave", function() GameTooltip:Hide() end) b:SetFrameStrata("DIALOG") b:SetFrameLevel((hostFrame.GetFrameLevel and hostFrame:GetFrameLevel() or 1) + 10) b:Show() hostFrame.BRPConfigButton = b
end
local function ShouldShowConfigButtonForSpell(spellID) if not spellID or spellID <= 0 then return false end if C_Spell and C_Spell.GetSpellName(spellID) == nil then return false end return addon:GetEventIDBySpellID(spellID) ~= nil end
local function IsLikelyAbilityRowHost(host) if not host or not host.GetObjectType or host:GetObjectType() ~= "Button" then return false end local w, h = host.GetWidth and host:GetWidth() or 0, host.GetHeight and host:GetHeight() or 0 return w >= 140 and h >= 14 end
local managedHosts = setmetatable({}, { __mode = "k" }) local MAX_HEADER_BUTTONS = 120
local function ScanEncounterHeaders()
    if not EncounterJournal or not EncounterJournal:IsShown() then return end local activeHosts = {}
    for i = 1, MAX_HEADER_BUTTONS do local headerButton = _G["EncounterJournalInfoHeader" .. i .. "HeaderButton"] if headerButton then local parent = headerButton:GetParent() local spellID = (parent and tonumber(parent.spellID)) or tonumber(headerButton.spellID) if spellID and ShouldShowConfigButtonForSpell(spellID) and IsLikelyAbilityRowHost(headerButton) then EnsureConfigButton(headerButton, spellID) activeHosts[headerButton] = true managedHosts[headerButton] = true end end end
    for host in pairs(managedHosts) do local btn = host.BRPConfigButton if btn then if activeHosts[host] then btn:Show() else btn.spellID = nil btn:Hide() end end end
end
local scanner = { scanning = false, queued = false }
local function RequestEncounterScan() if scanner.queued then return end scanner.queued = false if not EncounterJournal or not EncounterJournal:IsShown() then return end if scanner.scanning then return end scanner.scanning = true ScanEncounterHeaders() scanner.scanning = false end
local function HookEncounterJournal() if not EncounterJournal then return end if EncounterJournal.BRPHooked then return end EncounterJournal:HookScript("OnShow", RequestEncounterScan) EncounterJournal:HookScript("OnMouseUp", RequestEncounterScan) hooksecurefunc("EncounterJournal_ToggleHeaders", RequestEncounterScan) EncounterJournal.BRPHooked = true end
local ejEvent = CreateFrame("Frame") ejEvent:RegisterEvent("ADDON_LOADED") ejEvent:SetScript("OnEvent", function(_, event, arg1) if event == "ADDON_LOADED" and arg1 == "Blizzard_EncounterJournal" then HookEncounterJournal() ejEvent:RegisterEvent("EJ_DIFFICULTY_UPDATE") C_Timer.After(1, RequestEncounterScan) return end if event == "EJ_DIFFICULTY_UPDATE" then RequestEncounterScan() end end) if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then HookEncounterJournal() end
