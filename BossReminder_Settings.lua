-- BossReminder_Settings: 导出/导入、设置（专精、brLog）
local addon = _G.BossReminder
if not addon then return end

local L = addon.L or setmetatable({}, { __index = function(_, k) return k end })
local AceGUI = LibStub("AceGUI-3.0")
local TrimString, ParseTransferBoolean = addon.TrimString, addon.ParseTransferBoolean

local SPELL_CONFIG_DEFAULTS = { enabled = true, warningSound = "", highlightSound = "", textSound = "" }
local settingsFrame, transferFrame, transferEditBox, transferActionBtn
local brLogCb
local usePerSpecCb, specDropdown

local function IsSpellConfigModified(cfg)
    if type(cfg) ~= "table" then return false end
    if cfg.enabled ~= SPELL_CONFIG_DEFAULTS.enabled then return true end
    if (cfg.warningSound or "") ~= SPELL_CONFIG_DEFAULTS.warningSound then return true end
    if (cfg.highlightSound or "") ~= SPELL_CONFIG_DEFAULTS.highlightSound then return true end
    if (cfg.textSound or "") ~= SPELL_CONFIG_DEFAULTS.textSound then return true end
    return false
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

local function BuildExportText()
    if not C_EncodingUtil or type(C_EncodingUtil.SerializeJSON) ~= "function" or type(C_EncodingUtil.CompressString) ~= "function" or type(C_EncodingUtil.EncodeBase64) ~= "function" then
        return nil, "C_EncodingUtil unavailable"
    end
    local PREFIX, CMETHOD, CLEVEL = "BRP1:", (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0, (Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default) or 0
    local payload = { version = 1, entries = {} }
    local spells = addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells() or {}
    for spellID, cfg in pairs(spells) do
        if IsSpellConfigModified(cfg) then
            payload.entries[#payload.entries+1] = {
                spellID = tonumber(spellID), instanceID = tonumber(cfg.instanceID), journalInstanceID = tonumber(cfg.journalInstanceID),
                bossID = tonumber(cfg.bossID or cfg.encounterID), dungeonEncounterID = tonumber(cfg.dungeonEncounterID),
                enabled = cfg.enabled == false and false or true, warningSound = tostring(cfg.warningSound or ""), highlightSound = tostring(cfg.highlightSound or ""), textSound = tostring(cfg.textSound or ""),
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
                    warningSound = tostring(cfg.warningSound or ""),
                    highlightSound = tostring(cfg.highlightSound or ""),
                    textSound = tostring(cfg.textSound or ""),
                }
            end
        end
        if #specEntries > 0 then
            payload.specs[specKey] = { entries = specEntries }
        end
    end

    if p.specConfigs["default"] and p.specConfigs["default"].spells then
        addSpecEntries("default", p.specConfigs["default"].spells)
    end
    for specKey, spec in pairs(p.specConfigs) do
        if specKey ~= "default" and spec and spec.spells then
            addSpecEntries(specKey, spec.spells)
        end
    end

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

    if type(payload.specs) == "table" then
        local p = addon.db.profile
        p.specConfigs = {}
        p.spells = nil
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
                        cfg.warningSound = tostring(item.warningSound or "")
                        cfg.highlightSound = tostring(item.highlightSound or "")
                        cfg.textSound = tostring(item.textSound or "")
                        specSpells[spellID] = cfg
                        imported = imported + 1
                    else
                        skipped = skipped + 1
                    end
                end
                p.specConfigs[specKey] = { spells = specSpells }
            end
        end
    else
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
                    cfg.warningSound = tostring(item.warningSound or "")
                    cfg.highlightSound = tostring(item.highlightSound or "")
                    cfg.textSound = tostring(item.textSound or "")
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

local function OpenTransferWindow(mode)
    if not transferFrame then
        transferFrame = AceGUI:Create("Frame") transferFrame:SetWidth(700) transferFrame:SetHeight(420) transferFrame:SetLayout("Fill") transferFrame:SetCallback("OnClose", function(w) w.frame:Hide() end)
        local inner = AceGUI:Create("SimpleGroup") inner:SetLayout("List") inner:SetFullWidth(true) inner:SetFullHeight(true) transferFrame:AddChild(inner)
        transferEditBox = AceGUI:Create("MultiLineEditBox") transferEditBox:SetLabel("") transferEditBox:SetFullWidth(true) transferEditBox:SetNumLines(14) transferEditBox:DisableButton(true) inner:AddChild(transferEditBox)
        local btnRow = AceGUI:Create("SimpleGroup") btnRow:SetLayout("Flow") btnRow:SetFullWidth(true) inner:AddChild(btnRow)
        transferActionBtn = AceGUI:Create("Button") transferActionBtn:SetText(L.BUTTON_IMPORT) transferActionBtn:SetWidth(100)
        transferActionBtn:SetCallback("OnClick", function()
            local imported, skipped, err = ImportOverviewText(transferEditBox:GetText() or "")
            if err then transferEditBox:SetLabel(string.format(L.TRANSFER_ERROR_FMT or "错误: %s", err))
            else transferEditBox:SetLabel(string.format(L.TRANSFER_IMPORTED_FMT or "导入 %d 条，跳过 %d 条", imported, skipped)) transferFrame.frame:Hide() end
        end)
        btnRow:AddChild(transferActionBtn)
    end
    if mode == "export" then
        transferFrame:SetTitle(L.TRANSFER_EXPORT_TITLE or "导出")
        local text, err = BuildExportText()
        transferEditBox:SetLabel(L.TRANSFER_EXPORTING_FMT or "正在导出") transferEditBox:SetText(text or string.format(L.TRANSFER_EXPORT_FAILED_FMT or "导出失败: %s", tostring(err or L.UNKNOWN))) transferActionBtn:SetDisabled(true)
    elseif mode == "exportAll" then
        transferFrame:SetTitle(L.TRANSFER_EXPORT_TITLE or "导出")
        local text, err = BuildExportAllSpecsText()
        if transferEditBox then
            if text then
                transferEditBox:SetLabel(L.TRANSFER_EXPORTING_FMT or "正在导出")
                transferEditBox:SetText(text)
                transferActionBtn:SetDisabled(true)
            else
                transferEditBox:SetLabel(string.format(L.TRANSFER_EXPORT_FAILED_FMT or "导出失败: %s", tostring(err or L.UNKNOWN)))
            end
        end
        transferFrame.frame:Show() transferFrame.frame:Raise()
        return
    else
        transferFrame:SetTitle(L.TRANSFER_IMPORT_TITLE or "导入") transferEditBox:SetLabel(L.TRANSFER_IMPORT_HINT or "粘贴导入字符串") transferEditBox:SetText("") transferActionBtn:SetDisabled(false) transferActionBtn:SetText(L.BUTTON_IMPORT)
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

    local specHeader = AceGUI:Create("Heading") specHeader:SetText(L.OVERVIEW_SPEC or "专精") specHeader:SetFullWidth(true) body:AddChild(specHeader)
    local specRow = AceGUI:Create("SimpleGroup") specRow:SetLayout("Flow") specRow:SetFullWidth(true) body:AddChild(specRow)
    usePerSpecCb = AceGUI:Create("CheckBox") usePerSpecCb:SetLabel(L.OVERVIEW_USE_PER_SPEC or "按专精配置") usePerSpecCb:SetValue(addon:GetUsePerSpec()) usePerSpecCb:SetWidth(150)
    usePerSpecCb:SetCallback("OnValueChanged", function(_, _, val)
        addon:SetUsePerSpec(val)
        addon:SyncActiveProfile()
        addon:ForceUpdateAllSounds()
        if specDropdown then specDropdown:SetValue(addon:GetCurrentSpecKey()) end
    end)
    specRow:AddChild(usePerSpecCb)
    specDropdown = AceGUI:Create("Dropdown")
    specDropdown:SetLabel(L.OVERVIEW_SPEC or "专精")
    specDropdown:SetList(BuildSpecList())
    specDropdown:SetValue(addon:GetCurrentSpecKey())
    specDropdown:SetWidth(220)
    specDropdown:SetDisabled(true)
    specRow:AddChild(specDropdown)

    local ioHeader = AceGUI:Create("Heading") ioHeader:SetText(L.OVERVIEW_IO_HEADER or "导入 / 导出") ioHeader:SetFullWidth(true) body:AddChild(ioHeader)
    local ioRow = AceGUI:Create("SimpleGroup") ioRow:SetLayout("Flow") ioRow:SetFullWidth(true) body:AddChild(ioRow)
    local exportBtn = AceGUI:Create("Button") exportBtn:SetText(L.BUTTON_EXPORT) exportBtn:SetWidth(120)
    exportBtn:SetCallback("OnClick", function() OpenTransferWindow("export") end) ioRow:AddChild(exportBtn)
    local exportAllBtn = AceGUI:Create("Button") exportAllBtn:SetText(L.BUTTON_EXPORT_ALL or "导出所有专精") exportAllBtn:SetWidth(140)
    exportAllBtn:SetCallback("OnClick", function() OpenTransferWindow("exportAll") end) ioRow:AddChild(exportAllBtn)
    local importBtn = AceGUI:Create("Button") importBtn:SetText(L.BUTTON_IMPORT) importBtn:SetWidth(120)
    importBtn:SetCallback("OnClick", function() OpenTransferWindow("import") end) ioRow:AddChild(importBtn)

    local globalHeader = AceGUI:Create("Heading") globalHeader:SetText(L.OVERVIEW_GLOBAL_HEADER or "全局") globalHeader:SetFullWidth(true) body:AddChild(globalHeader)
    local globalRow = AceGUI:Create("SimpleGroup") globalRow:SetLayout("Flow") globalRow:SetFullWidth(true) body:AddChild(globalRow)
    local s = addon.db.profile.settings or {}
    brLogCb = AceGUI:Create("CheckBox") brLogCb:SetLabel(L.OVERVIEW_BRLOG or "BR日志") brLogCb:SetValue(s.brLogEnabled == true) brLogCb:SetWidth(140)
    brLogCb:SetCallback("OnValueChanged", function(_, _, val) addon:SetBrLogEnabled(val) end) globalRow:AddChild(brLogCb)
end

function addon.OpenSettings()
    BuildSettingsWindow()
    if settingsFrame and settingsFrame.frame then
        if specDropdown then specDropdown:SetValue(addon:GetCurrentSpecKey()) end
        settingsFrame.frame:Show()
        settingsFrame.frame:Raise()
    end
end

addon.OpenOverviewSettings = addon.OpenSettings
addon.OpenTransferWindow = OpenTransferWindow
