-- BossReminder_Overview: overview window, export/import, filters, minimap button
local addon = _G.BossReminder
if not addon then return end

local L = addon.L or setmetatable({}, { __index = function(_, k) return k end })
local AceGUI = LibStub("AceGUI-3.0")
local TrimString, ParseTransferBoolean, GetLSM = addon.TrimString, addon.ParseTransferBoolean, addon.GetLSM

local overviewAllData, overviewData = {}, {}
local resolvedInstanceNames, resolvedBossNames = {}, {}
local filterState = { text = "", enabled = true, disabled = true }
local mainFrame, overviewList, statusLabel
local transferFrame, transferEditBox, transferActionBtn
local filterEditWidget, filterEnabledCb, filterDisabledCb
local settingsFrame, brLogCb, countdownVoiceDropdown, countdownVoiceHintLabel
local usePerSpecCb, specDropdown

local SOUND_NONE_KEY = "__none__"
local COL = { instance = 0.22, boss = 0.26, spell = 0.20, enable = 0.14, delete = 0.14 }
local SPELL_CONFIG_DEFAULTS = { enabled = true, warningSound = "", highlightSound = "", shouldCountdown = false }

local function IsSpellConfigModified(cfg)
    if type(cfg) ~= "table" then return false end
    if cfg.enabled ~= SPELL_CONFIG_DEFAULTS.enabled then return true end
    if (cfg.warningSound or "") ~= SPELL_CONFIG_DEFAULTS.warningSound then return true end
    if (cfg.highlightSound or "") ~= SPELL_CONFIG_DEFAULTS.highlightSound then return true end
    if (cfg.shouldCountdown and true or false) ~= SPELL_CONFIG_DEFAULTS.shouldCountdown then return true end
    return false
end

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then return true end
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
end

local function ResolveInstanceName(instanceID)
    local id = tonumber(instanceID)
    if not id or id <= 0 then return nil end
    if resolvedInstanceNames[id] ~= nil then return resolvedInstanceNames[id] end
    local name = EnsureEncounterJournalLoaded() and EJ_GetInstanceInfo and EJ_GetInstanceInfo(id) or nil
    resolvedInstanceNames[id] = name or false
    return name
end

local function ResolveBossName(bossID)
    local id = tonumber(bossID)
    if not id or id <= 0 then return nil end
    if resolvedBossNames[id] ~= nil then return resolvedBossNames[id] end
    local name = EnsureEncounterJournalLoaded() and EJ_GetEncounterInfo and EJ_GetEncounterInfo(id) or nil
    resolvedBossNames[id] = name or false
    return name
end

local function BuildInstanceSummary(cfg)
    local id, journalID = tonumber(cfg.instanceID), tonumber(cfg.journalInstanceID)
    local name = journalID and journalID > 0 and ResolveInstanceName(journalID) or nil
    if id and id > 0 then return (name and name ~= "") and string.format("%s (%d)", name, id) or tostring(id) end
    return name or "-"
end

local function BuildBossSummary(cfg)
    local id = tonumber(cfg.bossID or cfg.encounterID)
    local name = id and id > 0 and ResolveBossName(id)
    if id and id > 0 then return (name and name ~= "") and string.format("%s (%d)", name, id) or tostring(id) end
    return name or "-"
end

local function BuildEntrySearchText(entry)
    return string.lower(table.concat({ tostring(entry.spellID or ""), tostring(entry.spellName or ""), tostring(entry.instanceLabel or ""), tostring(entry.bossLabel or "") }, "\031"))
end

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
        else
            local plainSelected = selected:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            dropdown:SetValue(list[plainSelected] and plainSelected or SOUND_NONE_KEY)
        end
    else dropdown:SetValue(SOUND_NONE_KEY) end
end

local function BuildSpecList()
    local list = { ["default"] = L.OVERVIEW_SPEC_DEFAULT or "默认" }
    if type(GetNumSpecializations) == "function" and type(GetSpecializationInfo) == "function" then
        for i = 1, (GetNumSpecializations() or 0) do
            local id, name = GetSpecializationInfo(i)
            if id and name then list[tostring(id)] = name end
        end
    end
    return list
end

local function GetHighlightDurationHintText()
    local value = (C_CVar and type(C_CVar.GetCVar) == "function" and C_CVar.GetCVar("encounterTimelineHighlightDuration")) or (type(GetCVar) == "function" and GetCVar("encounterTimelineHighlightDuration"))
    local durationMs = tonumber(value) or 0
    return string.format(L.OVERVIEW_HIGHLIGHT_DURATION_HINT, string.format("%.1f", durationMs / 1000))
end

-- Export / Import
local function BuildExportText(entries)
    if not C_EncodingUtil or type(C_EncodingUtil.SerializeJSON) ~= "function" or type(C_EncodingUtil.CompressString) ~= "function" or type(C_EncodingUtil.EncodeBase64) ~= "function" then
        return nil, "C_EncodingUtil unavailable"
    end
    local PREFIX, CMETHOD, CLEVEL = "BRP1:", (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0, (Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default) or 0
    local payload = { version = 1, entries = {} }
    local spells = addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells() or {}
    for _, entry in ipairs(entries) do
        local cfg = spells[entry.spellID]
        if cfg then
            payload.entries[#payload.entries+1] = {
                spellID = tonumber(entry.spellID), instanceID = tonumber(cfg.instanceID), journalInstanceID = tonumber(cfg.journalInstanceID),
                bossID = tonumber(cfg.bossID or cfg.encounterID), dungeonEncounterID = tonumber(cfg.dungeonEncounterID),
                enabled = cfg.enabled == false and false or true, shouldCountdown = cfg.shouldCountdown and true or false, warningSound = tostring(cfg.warningSound or ""),
            }
        end
    end
    local ok1, json = pcall(C_EncodingUtil.SerializeJSON, payload)
    if not ok1 or type(json) ~= "string" or json == "" then return nil, "SerializeJSON failed" end
    local ok2, compressed = pcall(C_EncodingUtil.CompressString, json, CMETHOD, CLEVEL)
    if not ok2 or type(compressed) ~= "string" or compressed == "" then return nil, "CompressString failed" end
    local ok3, encoded = pcall(C_EncodingUtil.EncodeBase64, compressed)
    if not ok3 or type(encoded) ~= "string" or encoded == "" then return nil, "EncodeBase64 failed" end
    return PREFIX .. encoded, nil
end

-- 导出所有专精：使用 BRP2，payload.specs[specKey].entries = {...}
local function BuildExportAllSpecsText()
    if not C_EncodingUtil or type(C_EncodingUtil.SerializeJSON) ~= "function" or type(C_EncodingUtil.CompressString) ~= "function" or type(C_EncodingUtil.EncodeBase64) ~= "function" then
        return nil, "C_EncodingUtil unavailable"
    end
    local PREFIX, CMETHOD, CLEVEL = "BRP2:", (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0, (Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default) or 0
    local payload = { version = 2, specs = {} }
    local p = addon.db.profile
    p.specConfigs = p.specConfigs or {}

    local function addSpecEntries(specKey, spells)
        if not spells or type(spells) ~= "table" then return end
        local specEntries = {}
        for spellID, cfg in pairs(spells) do
            if IsSpellConfigModified(cfg) then
                specEntries[#specEntries+1] = {
                    spellID = tonumber(spellID),
                    instanceID = tonumber(cfg.instanceID),
                    journalInstanceID = tonumber(cfg.journalInstanceID),
                    bossID = tonumber(cfg.bossID or cfg.encounterID),
                    dungeonEncounterID = tonumber(cfg.dungeonEncounterID),
                    enabled = cfg.enabled == false and false or true,
                    shouldCountdown = cfg.shouldCountdown and true or false,
                    warningSound = tostring(cfg.warningSound or ""),
                }
            end
        end
        if #specEntries > 0 then
            payload.specs[specKey] = { entries = specEntries }
        end
    end

    -- 先 default，再其它专精
    if p.specConfigs["default"] and p.specConfigs["default"].spells then
        addSpecEntries("default", p.specConfigs["default"].spells)
    end
    for specKey, spec in pairs(p.specConfigs) do
        if specKey ~= "default" and spec and spec.spells then
            addSpecEntries(specKey, spec.spells)
        end
    end

    -- 如果什么都没有，就直接失败
    if not next(payload.specs) then
        return nil, "No spec configs to export"
    end

    local ok1, json = pcall(C_EncodingUtil.SerializeJSON, payload)
    if not ok1 or type(json) ~= "string" or json == "" then return nil, "SerializeJSON failed" end
    local ok2, compressed = pcall(C_EncodingUtil.CompressString, json, CMETHOD, CLEVEL)
    if not ok2 or type(compressed) ~= "string" or compressed == "" then return nil, "CompressString failed" end
    local ok3, encoded = pcall(C_EncodingUtil.EncodeBase64, compressed)
    if not ok3 or type(encoded) ~= "string" or encoded == "" then return nil, "EncodeBase64 failed" end
    return PREFIX .. encoded, nil
end

local function ImportOverviewText(text)
    if not C_EncodingUtil or type(C_EncodingUtil.DecodeBase64) ~= "function" or type(C_EncodingUtil.DecompressString) ~= "function" or type(C_EncodingUtil.DeserializeJSON) ~= "function" then
        return 0, 0, "C_EncodingUtil unavailable"
    end
    local PREFIX_V1, PREFIX_V2 = "BRP1:", "BRP2:"
    local CMETHOD = (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0
    local token = TrimString(text):gsub("%s+", "")
    if token:sub(1, #PREFIX_V2) == PREFIX_V2 then
        token = token:sub(#PREFIX_V2 + 1)
    elseif token:sub(1, #PREFIX_V1) == PREFIX_V1 then
        token = token:sub(#PREFIX_V1 + 1)
    end
    if token == "" then return 0, 0, "Empty import text" end
    local ok1, compressed = pcall(C_EncodingUtil.DecodeBase64, token)
    if not ok1 or type(compressed) ~= "string" or compressed == "" then return 0, 0, "DecodeBase64 failed" end
    local ok2, json = pcall(C_EncodingUtil.DecompressString, compressed, CMETHOD)
    if not ok2 or type(json) ~= "string" or json == "" then return 0, 0, "DecompressString failed" end
    local ok3, payload = pcall(C_EncodingUtil.DeserializeJSON, json)
    if not ok3 or type(payload) ~= "table" then return 0, 0, "DeserializeJSON failed" end
    local imported, skipped = 0, 0

    -- 新版：payload.specs -> 多专精导入，覆盖所有专精配置
    if type(payload.specs) == "table" then
        local p = addon.db.profile
        p.specConfigs = {}
        p.spells = nil
        local firstKey
        for specKey, specData in pairs(payload.specs) do
            if type(specData) == "table" and type(specData.entries) == "table" then
                local specSpells = {}
                for _, item in ipairs(specData.entries) do
                    local spellID = tonumber(item and item.spellID)
                    if spellID and spellID > 0 then
                        local cfg = {
                            spellID = spellID,
                            instanceID = tonumber(item.instanceID) or nil,
                            journalInstanceID = tonumber(item.journalInstanceID) or nil,
                            bossID = tonumber(item.bossID) or nil,
                            dungeonEncounterID = tonumber(item.dungeonEncounterID) or nil,
                        }
                        cfg.encounterID = cfg.bossID
                        cfg.enabled = ParseTransferBoolean(item.enabled, true)
                        cfg.shouldCountdown = ParseTransferBoolean(item.shouldCountdown or item.countdown5s, false)
                        cfg.warningSound = tostring(item.warningSound or "")
                        specSpells[spellID] = cfg
                        imported = imported + 1
                    else
                        skipped = skipped + 1
                    end
                end
                p.specConfigs[specKey] = { spells = specSpells }
                if not firstKey then firstKey = specKey end
            end
        end
    else
        -- 旧版或单专精导入：只导入到当前选中专精
        local entries = payload.entries
        if type(entries) ~= "table" then return 0, 0, "Invalid payload" end
        for _, item in ipairs(entries) do
            local spellID = tonumber(item and item.spellID)
            if spellID and spellID > 0 then
                local cfg = addon:GetSpellConfig(spellID, true)
                if cfg then
                    cfg.spellID = spellID
                    cfg.instanceID = tonumber(item.instanceID) or nil
                    cfg.journalInstanceID = tonumber(item.journalInstanceID) or nil
                    cfg.bossID = tonumber(item.bossID) or nil
                    cfg.dungeonEncounterID = tonumber(item.dungeonEncounterID) or nil
                    cfg.encounterID = cfg.bossID
                    cfg.enabled = ParseTransferBoolean(item.enabled, true)
                    cfg.shouldCountdown = ParseTransferBoolean(item.shouldCountdown or item.countdown5s, false)
                    cfg.warningSound = tostring(item.warningSound or "")
                    local spells = addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells() or {}
                    spells[spellID] = cfg
                    imported = imported + 1
                else
                    skipped = skipped + 1
                end
            else
                skipped = skipped + 1
            end
        end
    end

    if imported > 0 then addon:SyncActiveProfile() addon:ForceUpdateAllSounds() end
    return imported, skipped, nil
end

local function SortOverviewData(a, b)
    if a.instanceLabel ~= b.instanceLabel then return a.instanceLabel < b.instanceLabel end
    if a.bossLabel ~= b.bossLabel then return a.bossLabel < b.bossLabel end
    return a.spellID < b.spellID
end

local RebuildList
local ApplyOverviewFilter
local RefreshOverviewData

local function DeleteSpellConfigLocal(spellID)
    local id = tonumber(spellID)
    if not id then return end
    local panel = _G.BossReminderConfigPanel
    if panel and panel.currentSpellID == id and panel.IsShown and panel:IsShown() then panel:Hide() panel.currentSpellID = nil end
    addon:RemoveSpellConfig(addon:GetCurrentSpecKey(), id)
    RefreshOverviewData()
end

local function DeleteAllSpellConfigsLocal()
    local panel = _G.BossReminderConfigPanel
    if panel then panel.currentSpellID = nil if panel.IsShown and panel:IsShown() then panel:Hide() end end
    addon:RemoveAllSpellConfigs(addon:GetCurrentSpecKey())
    RefreshOverviewData()
end

StaticPopupDialogs["BOSS_REMINDER_DELETE_ALL"] = {
    text = L.OVERVIEW_DELETE_ALL_CONFIRM, button1 = L.BUTTON_YES or YES, button2 = L.BUTTON_CANCEL or CANCEL,
    OnAccept = DeleteAllSpellConfigsLocal, timeout = 0, whileDead = true, preferredIndex = 3,
}

RebuildList = function()
    if not overviewList then return end
    overviewList:ReleaseChildren()
    local spells = addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells() or {}
    for _, entry in ipairs(overviewData) do
        local cfg = spells[entry.spellID]
        if cfg then
            local spellID = entry.spellID
            local row = AceGUI:Create("SimpleGroup")
            row:SetLayout("Flow") row:SetFullWidth(true)
            local instLbl = AceGUI:Create("InteractiveLabel") instLbl:SetText(entry.instanceLabel) instLbl:SetRelativeWidth(COL.instance) instLbl:SetCallback("OnClick", function() addon.OpenConfig(spellID) end) row:AddChild(instLbl)
            local bossLbl = AceGUI:Create("InteractiveLabel") bossLbl:SetText(entry.bossLabel) bossLbl:SetRelativeWidth(COL.boss) bossLbl:SetCallback("OnClick", function() addon.OpenConfig(spellID) end) row:AddChild(bossLbl)
            local spellLbl = AceGUI:Create("InteractiveLabel") spellLbl:SetText(entry.spellName or tostring(spellID)) spellLbl:SetRelativeWidth(COL.spell) spellLbl:SetCallback("OnClick", function() addon.OpenConfig(spellID) end)
            spellLbl:SetCallback("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self.frame, "ANCHOR_TOP") GameTooltip:SetSpellByID(spellID) GameTooltip:Show() end end)
            spellLbl:SetCallback("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end) row:AddChild(spellLbl)
            local enableBtn = AceGUI:Create("Button") enableBtn:SetText(cfg.enabled ~= false and L.BUTTON_DISABLE or L.BUTTON_ENABLE) enableBtn:SetRelativeWidth(COL.enable)
            enableBtn:SetCallback("OnClick", function() addon:SetSpellEnabled(spellID, cfg.enabled == false) ApplyOverviewFilter() end) row:AddChild(enableBtn)
            local deleteBtn = AceGUI:Create("Button") deleteBtn:SetText(L.BUTTON_DELETE) deleteBtn:SetRelativeWidth(COL.delete) deleteBtn:SetCallback("OnClick", function() DeleteSpellConfigLocal(spellID) end) row:AddChild(deleteBtn)
            overviewList:AddChild(row)
        end
    end
    if statusLabel then
        statusLabel:SetText("")
    end
end

ApplyOverviewFilter = function()
    local txt, showEnabled, showDisabled = string.lower(TrimString(filterState.text)), filterState.enabled, filterState.disabled
    table.wipe(overviewData)
    local spells = addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells() or {}
    for _, entry in ipairs(overviewAllData) do
        local cfg = spells[entry.spellID]
        local isEnabled = not cfg or cfg.enabled ~= false
        if ((isEnabled and showEnabled) or (not isEnabled and showDisabled)) and (txt == "" or string.find(entry.searchText, txt, 1, true)) then
            overviewData[#overviewData+1] = entry
        end
    end
    RebuildList()
end

RefreshOverviewData = function()
    table.wipe(overviewAllData) table.wipe(resolvedInstanceNames) table.wipe(resolvedBossNames)
    local spells = addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells() or {}
    for spellID, cfg in pairs(spells) do
        if IsSpellConfigModified(cfg) then
            local spellName = cfg.spellName or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or L.SPELL_UNKNOWN
            local entry = { spellID = spellID, spellName = spellName, instanceLabel = BuildInstanceSummary(cfg), bossLabel = BuildBossSummary(cfg) }
            entry.searchText = BuildEntrySearchText(entry) overviewAllData[#overviewAllData+1] = entry
        end
    end
    table.sort(overviewAllData, SortOverviewData)
    ApplyOverviewFilter()
    if specDropdown then specDropdown:SetValue(addon:GetCurrentSpecKey()) end
end

addon.RefreshOverviewData = RefreshOverviewData
addon.UpdateOverview = RefreshOverviewData

local function OpenTransferWindow(mode)
    if not transferFrame then
        transferFrame = AceGUI:Create("Frame") transferFrame:SetWidth(700) transferFrame:SetHeight(420) transferFrame:SetLayout("Fill") transferFrame:SetCallback("OnClose", function(w) w.frame:Hide() end)
        local inner = AceGUI:Create("SimpleGroup") inner:SetLayout("List") inner:SetFullWidth(true) inner:SetFullHeight(true) transferFrame:AddChild(inner)
        transferEditBox = AceGUI:Create("MultiLineEditBox") transferEditBox:SetLabel("") transferEditBox:SetFullWidth(true) transferEditBox:SetNumLines(14) transferEditBox:DisableButton(true) inner:AddChild(transferEditBox)
        local btnRow = AceGUI:Create("SimpleGroup") btnRow:SetLayout("Flow") btnRow:SetFullWidth(true) inner:AddChild(btnRow)
        transferActionBtn = AceGUI:Create("Button") transferActionBtn:SetText(L.BUTTON_IMPORT) transferActionBtn:SetWidth(100)
        transferActionBtn:SetCallback("OnClick", function()
            local imported, skipped, err = ImportOverviewText(transferEditBox:GetText() or "")
            if err then transferEditBox:SetLabel(string.format(L.TRANSFER_ERROR_FMT, err))
            else transferEditBox:SetLabel(string.format(L.TRANSFER_IMPORTED_FMT, imported, skipped)) transferFrame.frame:Hide() end
        end)
        btnRow:AddChild(transferActionBtn)
    end
    if mode == "export" then
        transferFrame:SetTitle(L.TRANSFER_EXPORT_TITLE)
        local text, err = BuildExportText(overviewData)
        transferEditBox:SetLabel(string.format(L.TRANSFER_EXPORTING_FMT, #overviewData)) transferEditBox:SetText(text or string.format(L.TRANSFER_EXPORT_FAILED_FMT, tostring(err or L.UNKNOWN))) transferActionBtn:SetDisabled(true)
    else
        transferFrame:SetTitle(L.TRANSFER_IMPORT_TITLE) transferEditBox:SetLabel(L.TRANSFER_IMPORT_HINT) transferEditBox:SetText("") transferActionBtn:SetDisabled(false) transferActionBtn:SetText(L.BUTTON_IMPORT)
    end
    transferFrame.frame:Show() transferFrame.frame:Raise()
end

local function BuildSettingsWindow()
    if settingsFrame then return end
    settingsFrame = AceGUI:Create("Window")
    settingsFrame:SetTitle(L.OVERVIEW_SETTINGS or "BossReminder 设置")
    settingsFrame:SetWidth(520) settingsFrame:SetHeight(420)
    settingsFrame:SetLayout("List")
    settingsFrame:SetCallback("OnClose", function(w) w.frame:Hide() end)

    local body = AceGUI:Create("SimpleGroup") body:SetLayout("List") body:SetFullWidth(true) body:SetFullHeight(true)
    settingsFrame:AddChild(body)

    -- 专精配置
    local specHeader = AceGUI:Create("Heading") specHeader:SetText(L.OVERVIEW_SPEC or "专精") specHeader:SetFullWidth(true) body:AddChild(specHeader)
    local specRow = AceGUI:Create("SimpleGroup") specRow:SetLayout("Flow") specRow:SetFullWidth(true) body:AddChild(specRow)
    usePerSpecCb = AceGUI:Create("CheckBox") usePerSpecCb:SetLabel(L.OVERVIEW_USE_PER_SPEC or "按专精配置") usePerSpecCb:SetValue(addon:GetUsePerSpec()) usePerSpecCb:SetWidth(150)
    usePerSpecCb:SetCallback("OnValueChanged", function(_, _, val)
        addon:SetUsePerSpec(val)
        addon:SyncActiveProfile()
        addon:ForceUpdateAllSounds()
        if specDropdown then specDropdown:SetValue(addon:GetCurrentSpecKey()) end
        RefreshOverviewData()
    end)
    specRow:AddChild(usePerSpecCb)
    specDropdown = AceGUI:Create("Dropdown")
    specDropdown:SetLabel(L.OVERVIEW_SPEC or "专精")
    specDropdown:SetList(BuildSpecList())
    specDropdown:SetValue(addon:GetCurrentSpecKey())
    specDropdown:SetWidth(220)
    specDropdown:SetDisabled(true)  -- 只读：按当前专精，仅显示不切换
    specRow:AddChild(specDropdown)

    -- 导入 / 导出
    local ioHeader = AceGUI:Create("Heading") ioHeader:SetText(L.OVERVIEW_IO_HEADER or "导入 / 导出") ioHeader:SetFullWidth(true) body:AddChild(ioHeader)
    local ioRow = AceGUI:Create("SimpleGroup") ioRow:SetLayout("Flow") ioRow:SetFullWidth(true) body:AddChild(ioRow)
    local exportBtn = AceGUI:Create("Button") exportBtn:SetText(L.BUTTON_EXPORT) exportBtn:SetWidth(120)
    exportBtn:SetCallback("OnClick", function() OpenTransferWindow("export") end) ioRow:AddChild(exportBtn)
    local exportAllBtn = AceGUI:Create("Button") exportAllBtn:SetText(L.BUTTON_EXPORT_ALL or "Export All Specs") exportAllBtn:SetWidth(140)
    exportAllBtn:SetCallback("OnClick", function()
        local text, err = BuildExportAllSpecsText()
        if not transferFrame then OpenTransferWindow("export") end
        if transferEditBox then
            if text then
                transferFrame:SetTitle(L.TRANSFER_EXPORT_TITLE)
                transferEditBox:SetLabel(string.format(L.TRANSFER_EXPORTING_FMT, 0))
                transferEditBox:SetText(text)
                transferActionBtn:SetDisabled(true)
            else
                transferEditBox:SetLabel(string.format(L.TRANSFER_EXPORT_FAILED_FMT, tostring(err or L.UNKNOWN)))
            end
        end
        transferFrame.frame:Show() transferFrame.frame:Raise()
    end) ioRow:AddChild(exportAllBtn)
    local importBtn = AceGUI:Create("Button") importBtn:SetText(L.BUTTON_IMPORT) importBtn:SetWidth(120)
    importBtn:SetCallback("OnClick", function() OpenTransferWindow("import") end) ioRow:AddChild(importBtn)

    -- 全局选项
    local globalHeader = AceGUI:Create("Heading") globalHeader:SetText(L.OVERVIEW_GLOBAL_HEADER or "全局") globalHeader:SetFullWidth(true) body:AddChild(globalHeader)
    local globalRow = AceGUI:Create("SimpleGroup") globalRow:SetLayout("Flow") globalRow:SetFullWidth(true) body:AddChild(globalRow)
    local s = addon.db.profile.settings or {}
    brLogCb = AceGUI:Create("CheckBox") brLogCb:SetLabel(L.OVERVIEW_BRLOG) brLogCb:SetValue(s.brLogEnabled == true) brLogCb:SetWidth(140)
    brLogCb:SetCallback("OnValueChanged", function(_, _, val) addon:SetBrLogEnabled(val) end) globalRow:AddChild(brLogCb)

    -- 倒数语音
    local soundHeader = AceGUI:Create("Heading") soundHeader:SetText(L.OVERVIEW_COUNTDOWN_VOICE) soundHeader:SetFullWidth(true) body:AddChild(soundHeader)
    local countdownGroup = AceGUI:Create("SimpleGroup") countdownGroup:SetLayout("Flow") countdownGroup:SetFullWidth(true) body:AddChild(countdownGroup)
    countdownVoiceDropdown = AceGUI:Create("Dropdown") countdownVoiceDropdown:SetLabel("") countdownVoiceDropdown:SetWidth(320)
    InitSoundDropdown(countdownVoiceDropdown, (addon.db.profile.settings and addon.db.profile.settings.countdownVoice) or "")
    countdownVoiceDropdown:SetCallback("OnValueChanged", function(_, _, value)
        addon:SetCountdownVoice((value and value ~= SOUND_NONE_KEY) and value or "")
        if value and value ~= SOUND_NONE_KEY and GetLSM then
            local lsm = GetLSM()
            if lsm then
                local path = lsm:Fetch("sound", value, true)
                if path and path ~= "" then PlaySoundFile(path, "Master") end
            end
        end
    end)
    countdownGroup:AddChild(countdownVoiceDropdown)
    countdownVoiceHintLabel = AceGUI:Create("Label") countdownVoiceHintLabel:SetFullWidth(true)
    countdownVoiceHintLabel:SetText(GetHighlightDurationHintText())
    body:AddChild(countdownVoiceHintLabel)
end

function addon.OpenOverviewSettings()
    BuildSettingsWindow()
    if settingsFrame and settingsFrame.frame then
        if specDropdown then specDropdown:SetValue(addon:GetCurrentSpecKey()) end
        settingsFrame.frame:Show()
        settingsFrame.frame:Raise()
    end
end

local function BuildOverviewWindow()
    mainFrame = AceGUI:Create("Window") mainFrame:SetTitle(L.OVERVIEW_TITLE) mainFrame:SetWidth(880) mainFrame:SetHeight(560) mainFrame:SetLayout("List") mainFrame:SetCallback("OnClose", function(w) w.frame:Hide() end)
    local filterGroup = AceGUI:Create("SimpleGroup") filterGroup:SetLayout("Flow") filterGroup:SetFullWidth(true) mainFrame:AddChild(filterGroup)
    filterEditWidget = AceGUI:Create("EditBox") filterEditWidget:SetLabel(L.OVERVIEW_FILTER) filterEditWidget:SetWidth(250) filterEditWidget:DisableButton(true) filterEditWidget:SetCallback("OnTextChanged", function(_, _, val) filterState.text = val or "" ApplyOverviewFilter() end) filterGroup:AddChild(filterEditWidget)
    filterEnabledCb = AceGUI:Create("CheckBox") filterEnabledCb:SetLabel(L.BUTTON_ENABLE) filterEnabledCb:SetValue(true) filterEnabledCb:SetWidth(95) filterEnabledCb:SetCallback("OnValueChanged", function(_, _, val) filterState.enabled = val ApplyOverviewFilter() end) filterGroup:AddChild(filterEnabledCb)
    filterDisabledCb = AceGUI:Create("CheckBox") filterDisabledCb:SetLabel(L.BUTTON_DISABLE) filterDisabledCb:SetValue(true) filterDisabledCb:SetWidth(95) filterDisabledCb:SetCallback("OnValueChanged", function(_, _, val) filterState.disabled = val ApplyOverviewFilter() end) filterGroup:AddChild(filterDisabledCb)
    local deleteAllBtn = AceGUI:Create("Button") deleteAllBtn:SetText(L.BUTTON_DELETE_ALL) deleteAllBtn:SetAutoWidth(true) deleteAllBtn:SetCallback("OnClick", function() StaticPopup_Show("BOSS_REMINDER_DELETE_ALL") end) filterGroup:AddChild(deleteAllBtn)
    local settingsBtn = AceGUI:Create("Button") settingsBtn:SetText(L.BUTTON_SETTINGS or "设置") settingsBtn:SetAutoWidth(true)
    settingsBtn:SetCallback("OnClick", function() if addon.OpenOverviewSettings then addon.OpenOverviewSettings() end end)
    filterGroup:AddChild(settingsBtn)
    local headerGroup = AceGUI:Create("SimpleGroup") headerGroup:SetLayout("Flow") headerGroup:SetFullWidth(true) mainFrame:AddChild(headerGroup)
    local function AddHeader(text, w) local lbl = AceGUI:Create("Label") lbl:SetText("|cffffd100" .. text .. "|r") lbl:SetRelativeWidth(w) headerGroup:AddChild(lbl) end
    AddHeader(L.HEADER_INSTANCE, COL.instance) AddHeader(L.HEADER_BOSS, COL.boss) AddHeader(L.HEADER_SPELL, COL.spell) AddHeader(L.HEADER_ACTION, COL.enable + COL.delete)
    local sep = AceGUI:Create("Heading") sep:SetFullWidth(true) sep:SetText("") mainFrame:AddChild(sep)
    overviewList = AceGUI:Create("ScrollFrame") overviewList:SetLayout("List") overviewList:SetFullWidth(true) overviewList:SetFullHeight(true) mainFrame:AddChild(overviewList)
    statusLabel = AceGUI:Create("Label") statusLabel:SetFullWidth(true) statusLabel:SetText("") mainFrame:AddChild(statusLabel)
    RefreshOverviewData()
end

function addon.OpenOverview()
    if mainFrame then
        mainFrame.frame:Show() mainFrame.frame:Raise() RefreshOverviewData()
    else BuildOverviewWindow() end
end
