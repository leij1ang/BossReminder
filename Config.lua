local _, ns = ...
local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
local AceGUI = LibStub("AceGUI-3.0")

-- Config Window state (AceGUI)
local panel = {
    currentSpellID = nil,
    currentEncounterContext = nil,
}

local configWindow
local soundDropdown
local highlightSoundDropdown
local countdownCheck
local statusLabel
local highlightWarnLabel
local countdownWarnLabel
local highlightWarnSpace1, highlightWarnSpace2
local countdownWarnSpace1, countdownWarnSpace2
local enableToggleButton
local SaveCurrentSpell

local SOUND_NONE_KEY = "__none__"

local function BuildCurrentSpellStatusText(spellName, spellID, enabled)
    local text = string.format(L.STATUS_CURRENT_SPELL_FMT, spellName, spellID)
    if enabled == false then
        text = text .. " " .. (L.STATUS_DISABLED_TAG or "[Disabled]")
    end
    return text
end

local function GetToggleButtonText(enabled)
    return enabled == false and L.BUTTON_ENABLE or L.BUTTON_DISABLE
end

local function HasSelectedSoundValue(value)
    return value ~= nil and value ~= "" and value ~= SOUND_NONE_KEY and value ~= L.NONE
end

local function IsChecked(value)
    return value == true or value == 1 or value == "1"
end

local function UpdateWarningVisibility()
    local hasHighlight = false
    local hasCountdown = false
    local highlightValue = nil
    local countdownValue = nil

    if highlightSoundDropdown then
        highlightValue = highlightSoundDropdown:GetValue()
        hasHighlight = HasSelectedSoundValue(highlightValue)
    end
    if countdownCheck then
        countdownValue = countdownCheck:GetValue()
        hasCountdown = IsChecked(countdownValue)
    end

    if highlightWarnLabel then
        if hasHighlight then
            highlightWarnLabel:SetText("|cffff0000" .. L.HIGHLIGHT_SOUND_WARN .. "|r")
            highlightWarnLabel.frame:Show()
            if highlightWarnSpace1 then highlightWarnSpace1.frame:Show() end
            if highlightWarnSpace2 then highlightWarnSpace2.frame:Show() end
        else
            highlightWarnLabel:SetText("")
            highlightWarnLabel.frame:Hide()
            if highlightWarnSpace1 then highlightWarnSpace1.frame:Hide() end
            if highlightWarnSpace2 then highlightWarnSpace2.frame:Hide() end
        end
    end

    if countdownWarnLabel then
        if hasCountdown then
            countdownWarnLabel:SetText("|cffff0000" .. L.COUNTDOWN_UNAVAILABLE .. "|r")
            countdownWarnLabel.frame:Show()
            if countdownWarnSpace1 then countdownWarnSpace1.frame:Show() end
            if countdownWarnSpace2 then countdownWarnSpace2.frame:Show() end
        else
            countdownWarnLabel:SetText("")
            countdownWarnLabel.frame:Hide()
            if countdownWarnSpace1 then countdownWarnSpace1.frame:Hide() end
            if countdownWarnSpace2 then countdownWarnSpace2.frame:Hide() end
        end
    end
end

-- Compatibility proxy for existing references from Main.lua.
_G.BossReminderConfigPanel = panel

function panel:IsShown()
    return configWindow and configWindow.frame and configWindow.frame:IsShown() or false
end

function panel:Hide()
    if configWindow and configWindow.frame then
        configWindow.frame:Hide()
    end
end

function panel:Raise()
    if configWindow and configWindow.frame then
        configWindow.frame:Raise()
    end
end

local function PromoteSpecialFrame(frameName)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == frameName then
            table.remove(UISpecialFrames, i)
        end
    end
    table.insert(UISpecialFrames, 1, frameName)
end

local function InitSoundDropdown(dropdown, selected)
    if not dropdown then
        return
    end

    local list = {
        [SOUND_NONE_KEY] = L.NONE,
    }

    local lsm = ns.GetLSM()
    if lsm then
        local sounds = lsm:List("sound") or {}
        table.sort(sounds, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for _, displayName in ipairs(sounds) do
            local plainName = displayName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            list[plainName] = displayName
            if displayName ~= plainName then
                list[displayName] = displayName
            end
        end
    end

    dropdown:SetList(list)
    if selected and selected ~= "" then
        if list[selected] then
            dropdown:SetValue(selected)
        else
            local plainSelected = selected:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if list[plainSelected] then
                dropdown:SetValue(plainSelected)
            else
                dropdown:SetValue(SOUND_NONE_KEY)
            end
        end
    else
        dropdown:SetValue(SOUND_NONE_KEY)
    end
end

local lsmCallbackRegistered = false
local lsmCallbackOwner = {}

function lsmCallbackOwner:OnRegistered(_, mediaType)
    if mediaType ~= "sound" then
        return
    end
    if panel:IsShown() then
        if soundDropdown then
            local selected = soundDropdown:GetValue()
            if selected == SOUND_NONE_KEY then selected = "" end
            InitSoundDropdown(soundDropdown, selected)
        end
        if highlightSoundDropdown then
            local selected = highlightSoundDropdown:GetValue()
            if selected == SOUND_NONE_KEY then selected = "" end
            InitSoundDropdown(highlightSoundDropdown, selected)
        end
    end
end

local function EnsureLSMCallback()
    if lsmCallbackRegistered then
        return
    end

    local lsm = ns.GetLSM()
    if not lsm or type(lsm.RegisterCallback) ~= "function" then
        return
    end

    lsm.RegisterCallback(lsmCallbackOwner, "LibSharedMedia_Registered", "OnRegistered")
    lsmCallbackRegistered = true
end

local function BuildConfigWindow()
    if configWindow then
        return
    end

    configWindow = AceGUI:Create("Window")
    configWindow:SetTitle(L.TITLE)
    configWindow:SetWidth(500)
    configWindow:SetHeight(360)
    configWindow:SetLayout("List")
    configWindow.frame:SetAlpha(0.9)
    configWindow:SetCallback("OnClose", function(w)
        w.frame:Hide()
    end)

    -- Register frame for Escape key close support.
    local escName = "BossReminderConfigFrame"
    _G[escName] = configWindow.frame
    PromoteSpecialFrame(escName)

    local body = AceGUI:Create("SimpleGroup")
    body:SetLayout("List")
    body:SetFullWidth(true)
    body:SetFullHeight(true)
    configWindow:AddChild(body)

    local soundLabel = AceGUI:Create("Label")
    soundLabel:SetText(L.SHARED_MEDIA)
    soundLabel:SetFullWidth(true)
    body:AddChild(soundLabel)

    local soundRow = AceGUI:Create("SimpleGroup")
    soundRow:SetLayout("Flow")
    soundRow:SetFullWidth(true)

    soundDropdown = AceGUI:Create("Dropdown")
    soundDropdown:SetLabel("")
    soundDropdown:SetWidth(260)
    soundDropdown:SetCallback("OnValueChanged", function(_, _, value)
        if value == SOUND_NONE_KEY then
            return
        end
        local lsm = ns.GetLSM()
        if not lsm then
            return
        end
        local soundPath = lsm:Fetch("sound", value, true)
        if soundPath and soundPath ~= "" then
            PlaySoundFile(soundPath, "Master")
        end
    end)
    soundRow:AddChild(soundDropdown)

    local soundPreviewButton = AceGUI:Create("Button")
    soundPreviewButton:SetText(L.BUTTON_PREVIEW)
    soundPreviewButton:SetAutoWidth(true)
    soundPreviewButton:SetCallback("OnClick", function()
        local value = soundDropdown:GetValue()
        if value and value ~= SOUND_NONE_KEY then
            local lsm = ns.GetLSM()
            if lsm then
                local soundPath = lsm:Fetch("sound", value, true)
                if soundPath and soundPath ~= "" then
                    PlaySoundFile(soundPath, "Master")
                end
            end
        end
    end)
    soundRow:AddChild(soundPreviewButton)

    body:AddChild(soundRow)

    local highlightRow = AceGUI:Create("SimpleGroup")
        local highlightSoundLabel = AceGUI:Create("Label")
    highlightSoundLabel:SetText(L.HIGHLIGHT_SOUND)
    highlightSoundLabel:SetFullWidth(true)
    highlightRow:AddChild(highlightSoundLabel)

    highlightRow:SetLayout("Flow")
    highlightRow:SetFullWidth(true)

    highlightSoundDropdown = AceGUI:Create("Dropdown")
    highlightSoundDropdown:SetLabel("")
    highlightSoundDropdown:SetWidth(260)
    highlightSoundDropdown:SetCallback("OnValueChanged", function(_, _, value)
        if HasSelectedSoundValue(value) and countdownCheck and IsChecked(countdownCheck:GetValue()) then
            countdownCheck:SetValue(false)
        end
        UpdateWarningVisibility()
        if not HasSelectedSoundValue(value) then
            return
        end
        local lsm = ns.GetLSM()
        if not lsm then
            return
        end
        local soundPath = lsm:Fetch("sound", value, true)
        if soundPath and soundPath ~= "" then
            PlaySoundFile(soundPath, "Master")
        end
    end)
    highlightRow:AddChild(highlightSoundDropdown)

    local highlightPreviewButton = AceGUI:Create("Button")
    highlightPreviewButton:SetText(L.BUTTON_PREVIEW)
    highlightPreviewButton:SetAutoWidth(true)
    highlightPreviewButton:SetCallback("OnClick", function()
        local value = highlightSoundDropdown:GetValue()
        if HasSelectedSoundValue(value) then
            local lsm = ns.GetLSM()
            if lsm then
                local soundPath = lsm:Fetch("sound", value, true)
                if soundPath and soundPath ~= "" then
                    PlaySoundFile(soundPath, "Master")
                end
            end
        end
    end)
    highlightRow:AddChild(highlightPreviewButton)

    body:AddChild(highlightRow)

    highlightWarnSpace1 = AceGUI:Create("Label")
    highlightWarnSpace1:SetText("")
    highlightWarnSpace1:SetFullWidth(true)
    highlightWarnSpace1.frame:Hide()
    body:AddChild(highlightWarnSpace1)

    highlightWarnLabel = AceGUI:Create("Label")
    highlightWarnLabel:SetText("")
    highlightWarnLabel:SetFullWidth(true)
    highlightWarnLabel.frame:Hide()
    body:AddChild(highlightWarnLabel)

    highlightWarnSpace2 = AceGUI:Create("Label")
    highlightWarnSpace2:SetText("")
    highlightWarnSpace2:SetFullWidth(true)
    highlightWarnSpace2.frame:Hide()
    body:AddChild(highlightWarnSpace2)

    countdownCheck = AceGUI:Create("CheckBox")
    countdownCheck:SetLabel(L.COUNTDOWN_5S)
    countdownCheck:SetValue(false)
    countdownCheck:SetFullWidth(true)
    countdownCheck:SetCallback("OnValueChanged", function(_, _, value)
        if IsChecked(value) and highlightSoundDropdown then
            local highlightValue = highlightSoundDropdown:GetValue()
            if HasSelectedSoundValue(highlightValue) then
                highlightSoundDropdown:SetValue(SOUND_NONE_KEY)
            end
        end
        UpdateWarningVisibility()
    end)
    body:AddChild(countdownCheck)

    countdownWarnSpace1 = AceGUI:Create("Label")
    countdownWarnSpace1:SetText("")
    countdownWarnSpace1:SetFullWidth(true)
    countdownWarnSpace1.frame:Hide()
    body:AddChild(countdownWarnSpace1)

    countdownWarnLabel = AceGUI:Create("Label")
    countdownWarnLabel:SetText("")
    countdownWarnLabel:SetFullWidth(true)
    countdownWarnLabel.frame:Hide()
    body:AddChild(countdownWarnLabel)

    countdownWarnSpace2 = AceGUI:Create("Label")
    countdownWarnSpace2:SetText("")
    countdownWarnSpace2:SetFullWidth(true)
    countdownWarnSpace2.frame:Hide()
    body:AddChild(countdownWarnSpace2)

    statusLabel = AceGUI:Create("Label")
    statusLabel:SetText(L.STATUS_OPEN_FROM_EJ)
    statusLabel:SetFullWidth(true)
    body:AddChild(statusLabel)

    local buttonRow = AceGUI:Create("SimpleGroup")
    buttonRow:SetLayout("Flow")
    buttonRow:SetFullWidth(true)
    body:AddChild(buttonRow)

    local overviewButton = AceGUI:Create("Button")
    overviewButton:SetText(L.BUTTON_OVERVIEW)
    overviewButton:SetWidth(100)
    overviewButton:SetCallback("OnClick", function()
        ns.OpenOverview()
    end)
    buttonRow:AddChild(overviewButton)

    local saveButton = AceGUI:Create("Button")
    saveButton:SetText(L.BUTTON_SAVE)
    saveButton:SetWidth(100)
    saveButton:SetCallback("OnClick", function()
        SaveCurrentSpell()
    end)
    buttonRow:AddChild(saveButton)

    enableToggleButton = AceGUI:Create("Button")
    enableToggleButton:SetText(L.BUTTON_DISABLE)
    enableToggleButton:SetAutoWidth(true)
    enableToggleButton:SetCallback("OnClick", function()
        local id = panel.currentSpellID
        if not id then
            statusLabel:SetText(L.STATUS_SAVE_NEED_SELECT)
            return
        end

        local cfg = ns.runtimeDB and ns.runtimeDB:getSpellConfig(id, true)
        if not cfg then
            statusLabel:SetText(L.STATUS_SAVE_INVALID)
            return
        end

        cfg.enabled = (cfg.enabled == false)

        if BossReminderDB and BossReminderDB.spells then
            BossReminderDB.spells[id] = cfg
        end

        if ns.runtimeDB and ns.runtimeDB.cacheSpells then
            ns.runtimeDB:cacheSpells(BossReminderDB and BossReminderDB.spells or {})
        end

        if cfg.enabled then
            if ns.ApplySoundConfig then
                ns.ApplySoundConfig(id)
            end
        else
            if ns.ClearSounds then
                ns.ClearSounds(id)
            end
        end

        local spellName = C_Spell.GetSpellName(id) or L.SPELL_UNKNOWN
        statusLabel:SetText(BuildCurrentSpellStatusText(spellName, id, cfg.enabled))
        enableToggleButton:SetText(GetToggleButtonText(cfg.enabled))

        if ns.RefreshOverviewData then
            ns.RefreshOverviewData()
        end
    end)
    buttonRow:AddChild(enableToggleButton)

    EnsureLSMCallback()
end



local function LoadSpell(spellID)
    BuildConfigWindow()

    local cfg, normalized = ns.runtimeDB:getSpellConfig(spellID, true)
    if not cfg then
        statusLabel:SetText(L.STATUS_INVALID_SPELL_ID)
        panel.currentSpellID = nil
        return
    end

    panel.currentSpellID = normalized
    countdownCheck:SetValue(cfg.shouldCountdown and true or false)
    InitSoundDropdown(soundDropdown, cfg.warningSound)
    InitSoundDropdown(highlightSoundDropdown, cfg.highlightSound)
    if cfg.highlightSound and cfg.highlightSound ~= "" then
        countdownCheck:SetValue(false)
    elseif cfg.shouldCountdown and highlightSoundDropdown then
        highlightSoundDropdown:SetValue(SOUND_NONE_KEY)
    end

    UpdateWarningVisibility()

    local spellName = C_Spell.GetSpellName(normalized) or L.SPELL_UNKNOWN
    statusLabel:SetText(BuildCurrentSpellStatusText(spellName, normalized, cfg.enabled))
    if enableToggleButton then
        enableToggleButton:SetText(GetToggleButtonText(cfg.enabled))
    end
end

local function GetCurrentEncounterContext()
    if type(EJ_GetEncounterInfo) ~= "function" then
        return nil
    end

    local encounterID
    if EncounterJournal then
        encounterID = tonumber(EncounterJournal.encounterID)
        if not encounterID and type(EncounterJournal.encounter) == "table" then
            encounterID = tonumber(EncounterJournal.encounter.encounterID)
            if not encounterID and type(EncounterJournal.encounter.info) == "table" then
                encounterID = tonumber(EncounterJournal.encounter.info.encounterID)
            end
        end
    end

    if not encounterID and EncounterJournalEncounterFrameInfo then
        encounterID = tonumber(EncounterJournalEncounterFrameInfo.encounterID)
    end
    if not encounterID then
        return nil
    end

    local _, _, _, _, _, journalInstanceID, dungeonEncounterID, instanceID = EJ_GetEncounterInfo(encounterID)

    return {
        encounterID = encounterID,
        bossID = encounterID,
        dungeonEncounterID = dungeonEncounterID,
        instanceID = instanceID,
        journalInstanceID = journalInstanceID,
    }
end

SaveCurrentSpell = function()
    BuildConfigWindow()

    local id = panel.currentSpellID
    if not id then
        statusLabel:SetText(L.STATUS_SAVE_NEED_SELECT)
        return
    end

    local cfg = ns.runtimeDB:getSpellConfig(id, true)
    if not cfg then
        statusLabel:SetText(L.STATUS_SAVE_INVALID)
        return
    end

    local selectedSound = soundDropdown and soundDropdown:GetValue() or SOUND_NONE_KEY
    cfg.warningSound = (selectedSound and selectedSound ~= SOUND_NONE_KEY) and selectedSound or ""
    local selectedHighlight = highlightSoundDropdown and highlightSoundDropdown:GetValue() or SOUND_NONE_KEY
    cfg.highlightSound = (selectedHighlight and selectedHighlight ~= SOUND_NONE_KEY) and selectedHighlight or ""
    if cfg.highlightSound ~= "" then
        cfg.shouldCountdown = false
        countdownCheck:SetValue(false)
    elseif IsChecked(countdownCheck:GetValue()) then
        cfg.shouldCountdown = true
        cfg.highlightSound = ""
        if highlightSoundDropdown then
            highlightSoundDropdown:SetValue(SOUND_NONE_KEY)
        end
    else
        cfg.shouldCountdown = false
    end

    local spellName = C_Spell.GetSpellName(id) or L.SPELL_UNKNOWN
    local encounterContext = panel.currentEncounterContext or GetCurrentEncounterContext()
    cfg.spellID = id
    cfg.bossID = (encounterContext and encounterContext.bossID) or cfg.bossID
    cfg.dungeonEncounterID = (encounterContext and encounterContext.dungeonEncounterID) or cfg.dungeonEncounterID
    cfg.instanceID = (encounterContext and encounterContext.instanceID) or cfg.instanceID
    cfg.journalInstanceID = (encounterContext and encounterContext.journalInstanceID) or cfg.journalInstanceID
    cfg.encounterID = (encounterContext and encounterContext.encounterID) or cfg.encounterID
    statusLabel:SetText(string.format(L.STATUS_SAVED_FMT, spellName, id))

    -- Sync to persistent database
    if BossReminderDB and BossReminderDB.spells then
        BossReminderDB.spells[id] = cfg
    end

    -- Update runtime cache
    if ns.runtimeDB and ns.runtimeDB.cacheSpells then
        ns.runtimeDB:cacheSpells(BossReminderDB and BossReminderDB.spells or {})
    end

    -- Apply or clear sound config based on whether sound is selected
    local hasAnySound = (selectedSound ~= SOUND_NONE_KEY and selectedSound ~= "")
        or (selectedHighlight ~= SOUND_NONE_KEY and selectedHighlight ~= "")
        or (cfg.shouldCountdown and BossReminderDB and BossReminderDB.countdownVoice and BossReminderDB.countdownVoice ~= "")
    if not hasAnySound then
        -- No sound available: clear settings
        if ns.ClearSounds then
            ns.ClearSounds(id)
        end
    else
        -- Apply sound config (including warning, reminder and countdown voice)
        if ns.ApplySoundConfig then
            ns.ApplySoundConfig(id)
        end
    end

    if ns.RefreshOverviewData then
        ns.RefreshOverviewData()
    end
end

function ns.OpenConfig(spellID)
    BuildConfigWindow()

    panel:Raise()
    panel.currentEncounterContext = GetCurrentEncounterContext()
    PromoteSpecialFrame("BossReminderConfigFrame")
    configWindow.frame:Show()
    LoadSpell(spellID)
end

-- ============================================================================
-- Encounter Journal (EJ) Integration
-- ============================================================================

local function EnsureConfigButton(hostFrame, spellID)
    if not hostFrame or not spellID then
        return
    end

    if hostFrame.BRPConfigButton then
        hostFrame.BRPConfigButton.spellID = spellID
        hostFrame.BRPConfigButton:Show()
        return
    end

    local b = CreateFrame("Button", nil, hostFrame, "UIPanelButtonTemplate")
    b:SetSize(20, 18)
    b:SetPoint("RIGHT", hostFrame, "RIGHT", -22, 0)
    b:SetText("C")
    b.spellID = spellID
    b:SetScript("OnClick", function(self)
        local currentSpellID = tonumber(self.spellID)
        if currentSpellID then
            ns.OpenConfig(currentSpellID)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TOOLTIP_CONFIG_SPELL, 1, 1, 1)
        if self.spellID then
            GameTooltip:AddLine(string.format(L.TOOLTIP_SPELL_ID_FMT, self.spellID), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    b:SetFrameStrata("DIALOG")
    b:SetFrameLevel((hostFrame.GetFrameLevel and hostFrame:GetFrameLevel() or 1) + 10)
    b:Show()

    hostFrame.BRPConfigButton = b
end

local function ShouldShowConfigButtonForSpell(spellID)
    if not spellID or spellID <= 0 then
        return false
    end
    if C_Spell.GetSpellName(spellID) == nil then
        return false
    end
    return ns.runtimeDB and ns.runtimeDB:getEventIDBySpellID(spellID) ~= nil
end

local function IsLikelyAbilityRowHost(host)
    if not host or not host.GetObjectType or host:GetObjectType() ~= "Button" then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    local height = host.GetHeight and host:GetHeight() or 0

    -- Filter out tiny utility/icon buttons to avoid repeated C in one row.
    if width < 140 or height < 14 then
        return false
    end

    return true
end

local managedHosts = setmetatable({}, { __mode = "k" })

local MAX_HEADER_BUTTONS = 120

local function ScanEncounterHeaders()
    if not EncounterJournal or not EncounterJournal:IsShown() then
        return
    end

    local activeHosts = {}
    local scannedHeaders = 0
    local matchedRows = 0

    for i = 1, MAX_HEADER_BUTTONS do
        local headerButton = _G["EncounterJournalInfoHeader" .. i .. "HeaderButton"]
        if headerButton then
            scannedHeaders = scannedHeaders + 1
            local parent = headerButton:GetParent()
            local spellID = (parent and tonumber(parent.spellID)) or tonumber(headerButton.spellID)

            if spellID and ShouldShowConfigButtonForSpell(spellID) and IsLikelyAbilityRowHost(headerButton) then
                EnsureConfigButton(headerButton, spellID)
                activeHosts[headerButton] = true
                managedHosts[headerButton] = true
                matchedRows = matchedRows + 1
            end
        end
    end

    for host in pairs(managedHosts) do
        local btn = host.BRPConfigButton
        if btn then
            if activeHosts[host] then
                btn:Show()
            else
                btn.spellID = nil
                btn:Hide()
            end
        end
    end

end

local scanner = {
    scanning = false,
    queued = false,
}

local function RequestEncounterScan()
    if scanner.queued then
        return
    end
    scanner.queued = true

    -- Test mode: disable deferred scan and run immediately.
    scanner.queued = false
    if not EncounterJournal or not EncounterJournal:IsShown() then
        return
    end

    if scanner.scanning then
        return
    end

    scanner.scanning = true
    ScanEncounterHeaders()
    scanner.scanning = false
end

local ejEvent = CreateFrame("Frame")
local function HookEncounterJournal()
    if not EncounterJournal then
        return
    end

    if EncounterJournal.BRPHooked then
        return
    end

    EncounterJournal:HookScript("OnShow", RequestEncounterScan)
    EncounterJournal:HookScript("OnMouseUp", RequestEncounterScan)
    hooksecurefunc("EncounterJournal_ToggleHeaders", RequestEncounterScan)

    EncounterJournal.BRPHooked = true
end

ejEvent:RegisterEvent("ADDON_LOADED")
ejEvent:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_EncounterJournal" then
        HookEncounterJournal()
        ejEvent:RegisterEvent("EJ_DIFFICULTY_UPDATE")
        C_Timer.After(1, RequestEncounterScan)
        return
    end

    if event == "EJ_DIFFICULTY_UPDATE" then
        RequestEncounterScan()
    end
end)

if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    HookEncounterJournal()
end
