local _, ns = ...
local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
local AceGUI = LibStub("AceGUI-3.0")

-- Forward declarations
local RefreshOverviewData
local ApplyOverviewFilter
local EnsureEncounterJournalLoaded
local DeleteSpellConfig
local DeleteAllSpellConfigs
local RebuildList

-- Data state
local overviewAllData      = {}
local overviewData         = {}
local resolvedInstanceNames = {}
local resolvedBossNames    = {}

-- Filter state
local filterState = { text = "", enabled = true, disabled = true }

-- UI references (created lazily)
local mainFrame          = nil  -- AceGUI Frame
local overviewList       = nil  -- AceGUI ScrollFrame
local statusLabel        = nil  -- AceGUI Label
local transferFrame      = nil  -- AceGUI Frame for export/import
local transferEditBox    = nil
local transferActionBtn  = nil
local filterEditWidget   = nil
local filterEnabledCb    = nil
local filterDisabledCb   = nil
local timelineLogCb      = nil
local countdownVoiceDropdown = nil
local countdownVoiceHintLabel = nil

local SOUND_NONE_KEY = "__none__"

-- Column relative widths (sum ~0.98 to avoid wrapping)
local COL = {
    instance = 0.22,
    boss     = 0.22,
    spell    = 0.26,
    enable   = 0.14,
    delete   = 0.14,
}

local SPELL_CONFIG_DEFAULTS = {
    enabled              = true,
    warningSound         = "",
    highlightSound       = "",
    shouldCountdown      = false,
}


-- ============================================================================
-- ============================================================================
-- Utility helpers
-- ============================================================================

local function IsSpellConfigModified(cfg)
    if type(cfg) ~= "table" then return false end
    if cfg.enabled ~= SPELL_CONFIG_DEFAULTS.enabled then return true end
    if (cfg.warningSound or "") ~= SPELL_CONFIG_DEFAULTS.warningSound then return true end
    if (cfg.highlightSound or "") ~= SPELL_CONFIG_DEFAULTS.highlightSound then return true end
    if (cfg.countdown5s and true or false) ~= SPELL_CONFIG_DEFAULTS.shouldCountdown then return true end
    return false
end

-- Utility helpers
local TrimString = ns.TrimString
local ParseTransferBoolean = ns.ParseTransferBoolean

local function GetLSM()
    if not LibStub then
        return nil
    end
    return LibStub("LibSharedMedia-3.0", true)
end

local function InitSoundDropdown(dropdown, selected)
    if not dropdown then
        return
    end

    local list = {
        [SOUND_NONE_KEY] = L.NONE,
    }

    local lsm = GetLSM()
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

local function BuildVoiceSummary(cfg)
    if cfg.warningSound and cfg.warningSound ~= "" then return cfg.warningSound end
    return "-"
end

local function GetHighlightDurationHintText()
    local value = nil
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        value = C_CVar.GetCVar("encounterTimelineHighlightDuration")
    elseif type(GetCVar) == "function" then
        value = GetCVar("encounterTimelineHighlightDuration")
    end

    local durationMs = tonumber(value) or 0
    local duration = string.format("%.1f", durationMs / 1000)  -- Convert milliseconds to seconds, keep 1 decimal place
    return string.format(L.OVERVIEW_HIGHLIGHT_DURATION_HINT, duration)
end

EnsureEncounterJournalLoaded = function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        return true
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_EncounterJournal")
    end
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
    local id = tonumber(cfg.instanceID)
    local journalID = tonumber(cfg.journalInstanceID)
    local name = journalID and journalID > 0 and ResolveInstanceName(journalID) or nil

    if id and id > 0 then
        return (name and name ~= "") and string.format("%s (%d)", name, id) or tostring(id)
    end
    return name or "-"
end

local function BuildBossSummary(cfg)
    local id   = tonumber(cfg.bossID or cfg.encounterID)
    local name = id and id > 0 and ResolveBossName(id)
    if id and id > 0 then
        return (name and name ~= "") and string.format("%s (%d)", name, id) or tostring(id)
    end
    return name or "-"
end

local function BuildEntrySearchText(entry)
    return string.lower(table.concat({
        tostring(entry.spellID or ""),
        tostring(entry.spellName or ""),
        tostring(entry.instanceLabel or ""),
        tostring(entry.bossLabel or ""),
    }, "\031"))
end

-- ============================================================================
-- Export / Import
-- ============================================================================

local function BuildExportText(entries)
    if not C_EncodingUtil
        or type(C_EncodingUtil.SerializeJSON)   ~= "function"
        or type(C_EncodingUtil.CompressString)  ~= "function"
        or type(C_EncodingUtil.EncodeBase64)    ~= "function"
    then
        return nil, "C_EncodingUtil unavailable"
    end

    local PREFIX = "BRP1:"
    local CMETHOD = (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0
    local CLEVEL  = (Enum and Enum.CompressionLevel  and Enum.CompressionLevel.Default)  or 0

    local payload = { version = 1, entries = {} }
    for _, entry in ipairs(entries) do
        local cfg = BossReminderDB and BossReminderDB.spells and BossReminderDB.spells[entry.spellID]
        if cfg then
            payload.entries[#payload.entries+1] = {
                spellID              = tonumber(entry.spellID),
                instanceID           = tonumber(cfg.instanceID),
                journalInstanceID    = tonumber(cfg.journalInstanceID),
                bossID               = tonumber(cfg.bossID or cfg.encounterID),
                dungeonEncounterID   = tonumber(cfg.dungeonEncounterID),
                enabled              = cfg.enabled == false and false or true,
                shouldCountdown      = cfg.shouldCountdown and true or false,
                warningSound         = tostring(cfg.warningSound or ""),
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

local function ImportOverviewText(text)
    if not C_EncodingUtil
        or type(C_EncodingUtil.DecodeBase64)     ~= "function"
        or type(C_EncodingUtil.DecompressString) ~= "function"
        or type(C_EncodingUtil.DeserializeJSON)  ~= "function"
    then
        return 0, 0, "C_EncodingUtil unavailable"
    end

    local PREFIX  = "BRP1:"
    local CMETHOD = (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0

    local token = TrimString(text):gsub("%s+", "")
    if token:sub(1, #PREFIX) == PREFIX then token = token:sub(#PREFIX + 1) end
    if token == "" then return 0, 0, "Empty import text" end

    local ok1, compressed = pcall(C_EncodingUtil.DecodeBase64, token)
    if not ok1 or type(compressed) ~= "string" or compressed == "" then return 0, 0, "DecodeBase64 failed" end

    local ok2, json = pcall(C_EncodingUtil.DecompressString, compressed, CMETHOD)
    if not ok2 or type(json) ~= "string" or json == "" then return 0, 0, "DecompressString failed" end

    local ok3, payload = pcall(C_EncodingUtil.DeserializeJSON, json)
    if not ok3 or type(payload) ~= "table" then return 0, 0, "DeserializeJSON failed" end

    local entries = payload.entries
    if type(entries) ~= "table" then return 0, 0, "Invalid payload" end

    local imported, skipped = 0, 0
    for _, item in ipairs(entries) do
        local spellID = tonumber(item and item.spellID)
        if spellID and spellID > 0 then
            local cfg = ns.runtimeDB:getSpellConfig(spellID, true)
            if cfg then
                cfg.spellID              = spellID
                cfg.instanceID           = tonumber(item.instanceID) or nil
                cfg.journalInstanceID    = tonumber(item.journalInstanceID) or nil
                cfg.bossID               = tonumber(item.bossID) or nil
                cfg.dungeonEncounterID   = tonumber(item.dungeonEncounterID) or nil
                cfg.encounterID          = cfg.bossID
                cfg.enabled              = ParseTransferBoolean(item.enabled, true)
                cfg.shouldCountdown      = ParseTransferBoolean(item.shouldCountdown or item.countdown5s, false)
                cfg.warningSound         = tostring(item.warningSound or "")
                -- Sync to persistent database
                if BossReminderDB and BossReminderDB.spells then
                    BossReminderDB.spells[spellID] = cfg
                end
                imported = imported + 1
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end

    RefreshOverviewData()
    return imported, skipped, nil
end

-- ============================================================================
-- Delete operations
-- ============================================================================

DeleteSpellConfig = function(spellID)
    local id = tonumber(spellID)
    if not id or not BossReminderDB or not BossReminderDB.spells then return end
    -- Clear sound settings
    if ns.ClearSounds then
        ns.ClearSounds(id)
    end
    -- Delete both runtime cache and persistent database
    BossReminderDB.spells[id] = nil
    if ns.runtimeDB then
        ns.runtimeDB:deleteSpellConfig(id)
    end
    local panel = _G.BossReminderConfigPanel
    if panel and panel.currentSpellID == id and panel:IsShown() then
        panel:Hide()
        panel.currentSpellID = nil
    end
    RefreshOverviewData()
end

DeleteAllSpellConfigs = function()
    if not BossReminderDB then return end
    -- Clear sound settings for all spells
    if ns.ClearSounds then
        for spellID in pairs(BossReminderDB.spells or {}) do
            ns.ClearSounds(tonumber(spellID))
        end
    end
    -- Clear both runtime cache and persistent database
    BossReminderDB.spells = {}
    if ns.runtimeDB then
        ns.runtimeDB:clearAllSpellConfigs()
    end
    local panel = _G.BossReminderConfigPanel
    if panel then
        panel.currentSpellID = nil
        if panel:IsShown() then panel:Hide() end
    end
    RefreshOverviewData()
end

StaticPopupDialogs["BOSS_REMINDER_DELETE_ALL"] = {
    text           = L.OVERVIEW_DELETE_ALL_CONFIRM,
    button1        = L.BUTTON_YES or YES,
    button2        = L.BUTTON_CANCEL or CANCEL,
    OnAccept       = DeleteAllSpellConfigs,
    timeout        = 0,
    whileDead      = true,
    preferredIndex = 3,
}

-- ============================================================================
-- Data / filter logic
-- ============================================================================

local function SortOverviewData(a, b)
    if a.instanceLabel ~= b.instanceLabel then return a.instanceLabel < b.instanceLabel end
    if a.bossLabel     ~= b.bossLabel     then return a.bossLabel     < b.bossLabel end
    return a.spellID < b.spellID
end

RebuildList = function()
    if not overviewList then return end
    overviewList:ReleaseChildren()

    for _, entry in ipairs(overviewData) do
        local cfg = BossReminderDB and BossReminderDB.spells[entry.spellID]
        local eventID = ns.runtimeDB and ns.runtimeDB:getEventIDBySpellID(entry.spellID)
        if cfg and eventID then

        local spellID = entry.spellID
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)

        -- Instance (clickable -> open config)
        local instLbl = AceGUI:Create("InteractiveLabel")
        instLbl:SetText(entry.instanceLabel)
        instLbl:SetRelativeWidth(COL.instance)
        instLbl:SetCallback("OnClick", function() ns.OpenConfig(spellID) end)
        row:AddChild(instLbl)

        -- Boss
        local bossLbl = AceGUI:Create("InteractiveLabel")
        bossLbl:SetText(entry.bossLabel)
        bossLbl:SetRelativeWidth(COL.boss)
        bossLbl:SetCallback("OnClick", function() ns.OpenConfig(spellID) end)
        row:AddChild(bossLbl)

        -- Spell name
        local spellLbl = AceGUI:Create("InteractiveLabel")
        spellLbl:SetText(entry.spellName or tostring(spellID))
        spellLbl:SetRelativeWidth(COL.spell)
        spellLbl:SetCallback("OnClick", function() ns.OpenConfig(spellID) end)
        spellLbl:SetCallback("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self.frame, "ANCHOR_TOP")
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:Show()
        end)
        spellLbl:SetCallback("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row:AddChild(spellLbl)

        -- Enable / Disable toggle
        local enableBtn = AceGUI:Create("Button")
        enableBtn:SetText(cfg.enabled ~= false and L.BUTTON_DISABLE or L.BUTTON_ENABLE)
        enableBtn:SetRelativeWidth(COL.enable)
        enableBtn:SetCallback("OnClick", function()
            cfg.enabled = (cfg.enabled == false)  -- false->true, true/nil->false
            -- Sync to database
            if BossReminderDB and BossReminderDB.spells then
                BossReminderDB.spells[spellID] = cfg
            end
            -- Update runtime cache
            if ns.runtimeDB and ns.runtimeDB.cacheSpells then
                ns.runtimeDB:cacheSpells(BossReminderDB and BossReminderDB.spells or {})
            end
            -- Apply or clear sound settings
            if cfg.enabled then
                if ns.ApplySoundConfig then
                    ns.ApplySoundConfig(spellID)
                end
            else
                if ns.ClearSounds then
                    ns.ClearSounds(spellID)
                end
            end
            ApplyOverviewFilter()
        end)
        row:AddChild(enableBtn)

        -- Delete
        local deleteBtn = AceGUI:Create("Button")
        deleteBtn:SetText(L.BUTTON_DELETE)
        deleteBtn:SetRelativeWidth(COL.delete)
        deleteBtn:SetCallback("OnClick", function()
            DeleteSpellConfig(spellID)
        end)
        row:AddChild(deleteBtn)

        overviewList:AddChild(row)
        end  -- if cfg
    end

    -- Status text
    if statusLabel then
        local txt = TrimString(filterState.text)
        if #overviewAllData == 0 then
            statusLabel:SetText(L.OVERVIEW_EMPTY)
        elseif txt ~= "" or not filterState.enabled or not filterState.disabled then
            statusLabel:SetText(string.format(L.OVERVIEW_SHOWING_FMT, #overviewData, #overviewAllData))
        else
            statusLabel:SetText(string.format(L.OVERVIEW_COUNT_FMT, #overviewData))
        end
    end
end

ApplyOverviewFilter = function()
    local txt         = string.lower(TrimString(filterState.text))
    local showEnabled  = filterState.enabled
    local showDisabled = filterState.disabled

    table.wipe(overviewData)
    for _, entry in ipairs(overviewAllData) do
        local cfg       = BossReminderDB and BossReminderDB.spells[entry.spellID]
        local isEnabled = not cfg or cfg.enabled ~= false
        local statusOk  = (isEnabled and showEnabled) or (not isEnabled and showDisabled)
        local textOk    = txt == "" or string.find(entry.searchText, txt, 1, true)
        if statusOk and textOk then
            overviewData[#overviewData+1] = entry
        end
    end

    RebuildList()
end

RefreshOverviewData = function()
    table.wipe(overviewAllData)
    table.wipe(resolvedInstanceNames)
    table.wipe(resolvedBossNames)

    for spellID, cfg in pairs((BossReminderDB and BossReminderDB.spells) or {}) do
        if IsSpellConfigModified(cfg) then
            local spellName = cfg.spellName or C_Spell.GetSpellName(spellID) or L.SPELL_UNKNOWN
            local entry = {
                spellID       = spellID,
                spellName     = spellName,
                instanceLabel = BuildInstanceSummary(cfg),
                bossLabel     = BuildBossSummary(cfg),
            }
            entry.searchText = BuildEntrySearchText(entry)
            overviewAllData[#overviewAllData+1] = entry
        end
    end

    table.sort(overviewAllData, SortOverviewData)
    ApplyOverviewFilter()
end

-- Expose for Config.lua
ns.RefreshOverviewData = RefreshOverviewData

-- ============================================================================
-- Transfer (Export / Import) window
-- ============================================================================

local function OpenTransferWindow(mode)
    if not transferFrame then
        transferFrame = AceGUI:Create("Frame")
        transferFrame:SetWidth(700)
        transferFrame:SetHeight(420)
        transferFrame:SetLayout("Fill")
        transferFrame:SetCallback("OnClose", function(w) w.frame:Hide() end)

        local inner = AceGUI:Create("SimpleGroup")
        inner:SetLayout("List")
        inner:SetFullWidth(true)
        inner:SetFullHeight(true)
        transferFrame:AddChild(inner)

        transferEditBox = AceGUI:Create("MultiLineEditBox")
        transferEditBox:SetLabel("")
        transferEditBox:SetFullWidth(true)
        transferEditBox:SetNumLines(14)
        transferEditBox:DisableButton(true)
        inner:AddChild(transferEditBox)

        local btnRow = AceGUI:Create("SimpleGroup")
        btnRow:SetLayout("Flow")
        btnRow:SetFullWidth(true)
        inner:AddChild(btnRow)

        transferActionBtn = AceGUI:Create("Button")
        transferActionBtn:SetText(L.BUTTON_IMPORT)
        transferActionBtn:SetWidth(100)
        transferActionBtn:SetCallback("OnClick", function()
            local imported, skipped, err = ImportOverviewText(transferEditBox:GetText() or "")
            if err then
                transferEditBox:SetLabel(string.format(L.TRANSFER_ERROR_FMT, err))
            else
                transferEditBox:SetLabel(string.format(L.TRANSFER_IMPORTED_FMT, imported, skipped))
                transferFrame.frame:Hide()
            end
        end)
        btnRow:AddChild(transferActionBtn)
    end

    if mode == "export" then
        transferFrame:SetTitle(L.TRANSFER_EXPORT_TITLE)
        local text, err = BuildExportText(overviewData)
        transferEditBox:SetLabel(string.format(L.TRANSFER_EXPORTING_FMT, #overviewData))
        transferEditBox:SetText(text or string.format(L.TRANSFER_EXPORT_FAILED_FMT, tostring(err or L.UNKNOWN)))
        transferActionBtn:SetDisabled(true)
    else
        transferFrame:SetTitle(L.TRANSFER_IMPORT_TITLE)
        transferEditBox:SetLabel(L.TRANSFER_IMPORT_HINT)
        transferEditBox:SetText("")
        transferActionBtn:SetDisabled(false)
        transferActionBtn:SetText(L.BUTTON_IMPORT)
    end

    transferFrame.frame:Show()
    transferFrame.frame:Raise()
end

-- ============================================================================
-- Overview window
-- ============================================================================

local function PromoteSpecialFrame(frameName)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == frameName then
            table.remove(UISpecialFrames, i)
        end
    end
    table.insert(UISpecialFrames, 1, frameName)
end

local function BuildOverviewWindow()
    mainFrame = AceGUI:Create("Window")
    mainFrame:SetTitle(L.OVERVIEW_TITLE)
    mainFrame:SetWidth(880)
    mainFrame:SetHeight(560)
    mainFrame:SetLayout("List")
    mainFrame:SetCallback("OnClose", function(w) w.frame:Hide() end)

    -- Register frame for Escape key close support.
    local escName = "BossReminderOverviewFrame"
    _G[escName] = mainFrame.frame
    PromoteSpecialFrame(escName)

    -- ---- Filter bar ----
    local filterGroup = AceGUI:Create("SimpleGroup")
    filterGroup:SetLayout("Flow")
    filterGroup:SetFullWidth(true)
    mainFrame:AddChild(filterGroup)

    filterEditWidget = AceGUI:Create("EditBox")
    filterEditWidget:SetLabel(L.OVERVIEW_FILTER)
    filterEditWidget:SetWidth(250)
    filterEditWidget:DisableButton(true)
    filterEditWidget:SetCallback("OnTextChanged", function(_, _, val)
        filterState.text = val or ""
        ApplyOverviewFilter()
    end)
    filterGroup:AddChild(filterEditWidget)

    filterEnabledCb = AceGUI:Create("CheckBox")
    filterEnabledCb:SetLabel(L.BUTTON_ENABLE)
    filterEnabledCb:SetValue(true)
    filterEnabledCb:SetWidth(95)
    filterEnabledCb:SetCallback("OnValueChanged", function(_, _, val)
        filterState.enabled = val
        ApplyOverviewFilter()
    end)
    filterGroup:AddChild(filterEnabledCb)

    filterDisabledCb = AceGUI:Create("CheckBox")
    filterDisabledCb:SetLabel(L.BUTTON_DISABLE)
    filterDisabledCb:SetValue(true)
    filterDisabledCb:SetWidth(95)
    filterDisabledCb:SetCallback("OnValueChanged", function(_, _, val)
        filterState.disabled = val
        ApplyOverviewFilter()
    end)
    filterGroup:AddChild(filterDisabledCb)

    timelineLogCb = AceGUI:Create("CheckBox")
    timelineLogCb:SetLabel(L.OVERVIEW_TIMELINE_LOG)
    timelineLogCb:SetValue(BossReminderDB and BossReminderDB.timelineLogs ~= false)
    timelineLogCb:SetWidth(140)
    timelineLogCb:SetCallback("OnValueChanged", function(_, _, val)
        BossReminderDB = BossReminderDB or {}
        BossReminderDB.timelineLogs = val and true or false
    end)
    filterGroup:AddChild(timelineLogCb)

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText(L.BUTTON_EXPORT)
    exportBtn:SetAutoWidth(true)
    exportBtn:SetCallback("OnClick", function() OpenTransferWindow("export") end)
    filterGroup:AddChild(exportBtn)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText(L.BUTTON_IMPORT)
    importBtn:SetAutoWidth(true)
    importBtn:SetCallback("OnClick", function() OpenTransferWindow("import") end)
    filterGroup:AddChild(importBtn)

    local deleteAllBtn = AceGUI:Create("Button")
    deleteAllBtn:SetText(L.BUTTON_DELETE_ALL)
    deleteAllBtn:SetAutoWidth(true)
    deleteAllBtn:SetCallback("OnClick", function() StaticPopup_Show("BOSS_REMINDER_DELETE_ALL") end)
    filterGroup:AddChild(deleteAllBtn)

    local countdownGroup = AceGUI:Create("SimpleGroup")
    countdownGroup:SetLayout("Flow")
    countdownGroup:SetFullWidth(true)
    mainFrame:AddChild(countdownGroup)

    countdownVoiceDropdown = AceGUI:Create("Dropdown")
    countdownVoiceDropdown:SetLabel(L.OVERVIEW_COUNTDOWN_VOICE)
    countdownVoiceDropdown:SetWidth(360)
    InitSoundDropdown(countdownVoiceDropdown, BossReminderDB and BossReminderDB.countdownVoice or "")
    countdownVoiceDropdown:SetCallback("OnValueChanged", function(_, _, value)
        BossReminderDB = BossReminderDB or {}
        BossReminderDB.countdownVoice = (value and value ~= SOUND_NONE_KEY) and value or ""

        if value and value ~= SOUND_NONE_KEY then
            local lsm = GetLSM()
            if lsm then
                local soundPath = lsm:Fetch("sound", value, true)
                if soundPath and soundPath ~= "" then
                    PlaySoundFile(soundPath, "Master")
                end
            end
        end
    end)
    countdownGroup:AddChild(countdownVoiceDropdown)

    countdownVoiceHintLabel = AceGUI:Create("Label")
    countdownVoiceHintLabel:SetFullWidth(true)
    countdownVoiceHintLabel:SetText(GetHighlightDurationHintText())
    countdownGroup:AddChild(countdownVoiceHintLabel)

    -- ---- Column headers ----
    local headerGroup = AceGUI:Create("SimpleGroup")
    headerGroup:SetLayout("Flow")
    headerGroup:SetFullWidth(true)
    mainFrame:AddChild(headerGroup)

    local function AddHeader(text, relWidth)
        local lbl = AceGUI:Create("Label")
        lbl:SetText("|cffffd100" .. text .. "|r")
        lbl:SetRelativeWidth(relWidth)
        headerGroup:AddChild(lbl)
    end
    AddHeader(L.HEADER_INSTANCE, COL.instance)
    AddHeader(L.HEADER_BOSS,     COL.boss)
    AddHeader(L.HEADER_SPELL,    COL.spell)
    AddHeader(L.HEADER_ACTION, COL.enable + COL.delete)

    -- ---- Separator ----
    local sep = AceGUI:Create("Heading")
    sep:SetFullWidth(true)
    sep:SetText("")
    mainFrame:AddChild(sep)

    -- ---- Scrollable list ----
    overviewList = AceGUI:Create("ScrollFrame")
    overviewList:SetLayout("List")
    overviewList:SetFullWidth(true)
    overviewList:SetFullHeight(true)
    mainFrame:AddChild(overviewList)

    -- ---- Status label ----
    statusLabel = AceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    statusLabel:SetText("")
    mainFrame:AddChild(statusLabel)

    RefreshOverviewData()
end

-- ============================================================================
-- Public API
-- ============================================================================

function ns.OpenOverview()
    if mainFrame then
        PromoteSpecialFrame("BossReminderOverviewFrame")
        if countdownVoiceDropdown then
            InitSoundDropdown(countdownVoiceDropdown, BossReminderDB and BossReminderDB.countdownVoice or "")
        end
        if countdownVoiceHintLabel then
            countdownVoiceHintLabel:SetText(GetHighlightDurationHintText())
        end
        mainFrame.frame:Show()
        mainFrame.frame:Raise()
        RefreshOverviewData()
    else
        BuildOverviewWindow()
    end
end

-- ============================================================================
-- LibDBIcon minimap button
-- ============================================================================

local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("BossReminder", {
    type = "launcher",
    icon = "Interface\\AddOns\\BossReminder\\BossReminder.tga",
    OnClick = function(self, button)
        if button == "LeftButton" then
            ns.OpenOverview()
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddLine("BossReminder")
        tt:AddLine(L.TOOLTIP_MINIMAP_HINT or "Click to toggle Overview", 0.8, 0.8, 0.8)
    end,
})

if not BossReminderDB.minimapIcon then
    BossReminderDB.minimapIcon = {}
end
LibStub("LibDBIcon-1.0"):Register("BossReminder", ldb, BossReminderDB.minimapIcon)

