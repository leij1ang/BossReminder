-- BossReminder_UI: 原生 WoW UI - 当前赛季/版本地下城/团本 tab、副本、首领、法术表格
local addon = _G.BossReminder
if not addon then return end

local L = addon.L or setmetatable({}, { __index = function(_, k) return k end })
local brLog = addon.brLog
local SOUND_NONE_KEY = addon.SOUND_NONE_KEY or "__none__"

local mainFrame, instanceScroll, instanceScrollBar, bossScroll, spellScroll
local instanceContent, bossContent, spellContent
local instanceButtons, bossButtons, spellRows = {}, {}, {}
local bossScrollBox, bossScrollBar, bossScrollView
local spellScrollBox, spellScrollBar, spellScrollView
local spellHeaderFrame
local useScrollBox = nil
local seasonDungeonTab, buildDungeonTab, buildRaidTab
local encounterSpellCache = {}
local MAX_SECTION_DEPTH = 20

local state = {
    mode = "season_dungeon", -- "season_dungeon" | "build_dungeon" | "build_raid"
    selectedInstanceId = nil,
    selectedEncounterId = nil,
    instanceIds = {},
    bosses = {},
    spells = {},
}

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then return true end
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
end

local function CanUseScrollBox()
    if useScrollBox == nil then
        EnsureEncounterJournalLoaded()
        if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
        useScrollBox = not not (CreateScrollBoxListLinearView and ScrollUtil and CreateDataProvider)
    end
    return useScrollBox
end

local function GetCurrentSeason()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        local s = C_MythicPlus.GetCurrentSeason()
        if s and s > 0 then return s end
    end
    return nil
end

local function CollectSpellsFromSection(sectionID, depth, out)
    if not sectionID or depth > MAX_SECTION_DEPTH then return end
    if not C_EncounterJournal or not C_EncounterJournal.GetSectionInfo then return end
    local info = C_EncounterJournal.GetSectionInfo(sectionID)
    if not info then return end
    if info.spellID and info.spellID ~= 0 then out[info.spellID] = true end
    if info.firstChildSectionID then CollectSpellsFromSection(info.firstChildSectionID, depth + 1, out) end
    if info.siblingSectionID then CollectSpellsFromSection(info.siblingSectionID, depth, out) end
end

local function GetEncounterSpells(encounterID)
    if encounterSpellCache[encounterID] then return encounterSpellCache[encounterID] end
    if not EnsureEncounterJournalLoaded() or not EJ_GetEncounterInfo then return {} end
    local _, _, _, rootSectionID = EJ_GetEncounterInfo(encounterID)
    if not rootSectionID then return {} end
    local spellSet = {}
    CollectSpellsFromSection(rootSectionID, 0, spellSet)
    local list = {}
    for spellID in pairs(spellSet) do list[#list + 1] = spellID end
    encounterSpellCache[encounterID] = list
    return list
end

local function PreloadInstanceSpells()
    if not EnsureEncounterJournalLoaded() or not EJ_SelectInstance or not EJ_GetEncounterInfoByIndex then return end
    local loaded = 0
    local function loadFromData(data)
        if not data or type(data) ~= "table" then return end
        for _, instId in ipairs(data.dungeon or data.mythic or {}) do
            if type(instId) == "number" and instId > 0 then
                EJ_SelectInstance(instId)
                local i = 1
                while true do
                    local _, _, encounterId = EJ_GetEncounterInfoByIndex(i, instId)
                    if not encounterId then break end
                    GetEncounterSpells(encounterId)
                    loaded = loaded + 1
                    i = i + 1
                end
            end
        end
        for _, instId in ipairs(data.raid or {}) do
            if type(instId) == "number" and instId > 0 then
                EJ_SelectInstance(instId)
                local i = 1
                while true do
                    local _, _, encounterId = EJ_GetEncounterInfoByIndex(i, instId)
                    if not encounterId then break end
                    GetEncounterSpells(encounterId)
                    loaded = loaded + 1
                    i = i + 1
                end
            end
        end
    end
    if addon.SeasonInstances then
        for _, data in pairs(addon.SeasonInstances) do loadFromData(data) end
    end
    if addon.BuildVersionInstances then
        for _, data in pairs(addon.BuildVersionInstances) do loadFromData(data) end
    end
    if brLog then brLog("PreloadInstanceSpells: %d encounters cached", loaded) end
end

local function ResolveInstanceName(instanceID)
    if not instanceID or instanceID <= 0 then return nil end
    if not EnsureEncounterJournalLoaded() or not EJ_GetInstanceInfo then return nil end
    return EJ_GetInstanceInfo(instanceID)
end

local function ResolveSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local n = C_Spell.GetSpellName(spellID)
        if n and n ~= "" then return n end
    end
    if GetSpellInfo then
        local n = GetSpellInfo(spellID)
        if n and n ~= "" then return n end
    end
    return nil
end

local function CreateScrollFrame(parent, contentName)
    local scroll = CreateFrame("ScrollFrame", contentName .. "Scroll", parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", contentName .. "Content", scroll)
    scroll:SetScrollChild(content)
    content:SetSize(parent:GetWidth() - 30, 1)
    scroll.content = content
    return scroll, content
end

local function CreateHorizontalScrollFrame(parent, contentName)
    local scroll = CreateFrame("ScrollFrame", contentName .. "Scroll", parent)
    local content = CreateFrame("Frame", contentName .. "Content", scroll)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetHorizontalScroll()
        local maxScroll = math.max(0, (content:GetWidth() or 0) - self:GetWidth())
        local newVal = math.max(0, math.min(maxScroll, cur - delta * 50))
        self:SetHorizontalScroll(newVal)
        if self.scrollBar then self.scrollBar:SetValue(newVal) end
    end)
    return scroll, content
end

local function CreateListButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetText(text)
    btn:SetHeight(24)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function UpdateSpellConfig(spellID, field, value)
    local cfg = addon:GetSpellConfig(spellID, true)
    if not cfg then return end
    local val = (value and value ~= SOUND_NONE_KEY) and value or ""
    cfg[field] = val
    if state.selectedEncounterId and not cfg.bossID then cfg.bossID = state.selectedEncounterId cfg.encounterID = state.selectedEncounterId end
    if state.selectedInstanceId and not cfg.instanceID then cfg.instanceID = state.selectedInstanceId cfg.journalInstanceID = state.selectedInstanceId end
    addon:SaveSpellConfigToProfile(addon:GetCurrentSpecKey(), spellID, cfg)
    if addon.SetSoundBySpellTrigger then addon:SetSoundBySpellTrigger(spellID, field, val) end
end

local function ClearSpellConfig(spellID)
    local eventID = addon:GetEventIDBySpellID(spellID)
    if eventID then
        local T = Enum.EncounterEventSoundTrigger
        pcall(C_EncounterEvents.SetEventSound, eventID, T.OnTimelineEventFinished, nil)
        pcall(C_EncounterEvents.SetEventSound, eventID, T.OnTimelineEventHighlight, nil)
        pcall(C_EncounterEvents.SetEventSound, eventID, T.OnTextWarningShown, nil)
    end
    addon:RemoveSpellConfig(addon:GetCurrentSpecKey(), spellID)
end

local function RefreshInstanceList()
    if not instanceContent then return end
    for _, f in ipairs(instanceButtons) do f:Hide() f:SetParent(nil) end
    table.wipe(instanceButtons)
    if state.mode == "season_dungeon" then
        local season = GetCurrentSeason()
        if addon.SeasonInstances then
            local maxS = 0
            for s in pairs(addon.SeasonInstances) do if type(s) == "number" and s > maxS then maxS = s end end
            if not season or not addon.SeasonInstances[season] then season = maxS > 0 and maxS or nil end
        end
        state.instanceIds = addon.GetInstance and addon.GetInstance(season, false) or {}
    else
        state.instanceIds = addon.GetInstanceByBuildVersion and addon.GetInstanceByBuildVersion(nil, state.mode == "build_raid") or {}
    end
    if #state.instanceIds == 0 then
        local msg = string.format("[BossReminder] 副本列表为空 mode=%s", tostring(state.mode))
        if brLog then brLog("%s", msg) else print(msg) end
    end
    local x = 0
    for _, instId in ipairs(state.instanceIds) do
        local name = ResolveInstanceName(instId) or tostring(instId)
        local btn = CreateListButton(instanceContent, name, function()
            state.selectedInstanceId = instId
            state.selectedEncounterId = nil
            addon._RefreshBossList()
            addon._RefreshSpellTable()
            if addon._UpdateTabHighlight then addon._UpdateTabHighlight() end
        end)
        btn:SetWidth(math.max(100, #name * 8 + 20))
        btn:SetPoint("TOPLEFT", instanceContent, "TOPLEFT", x, 0)
        btn:Show()
        instanceButtons[#instanceButtons + 1] = btn
        btn.instId = instId
        x = x + btn:GetWidth() + 4
    end
    instanceContent:SetSize(math.max(x, 1), 28)
    if instanceScroll and instanceScrollBar then
        local contentW = math.max(x, 1)
        local scrollW = instanceScroll:GetWidth() or 0
        local maxScroll = math.max(0, contentW - scrollW)
        if maxScroll > 0 then
            instanceScrollBar:SetMinMaxValues(0, maxScroll)
            instanceScrollBar:SetValue(instanceScroll:GetHorizontalScroll())
            instanceScrollBar:Show()
        else
            instanceScrollBar:Hide()
        end
    end
end

local BOSS_ROW_HEIGHT = 28

local function InitBossRow(frame, elementData)
    if not frame.btn then
        frame.btn = CreateListButton(frame, "", function() end)
        frame.btn:SetPoint("TOPLEFT", frame)
        frame.btn:SetPoint("BOTTOMRIGHT", frame)
    end
    local name, encounterId = elementData.name, elementData.encounterId
    frame.btn:SetText(name or tostring(encounterId))
    frame.btn.encounterId = encounterId
    frame.btn:SetScript("OnClick", function()
        state.selectedEncounterId = encounterId
        local allSpells = GetEncounterSpells(encounterId)
        local count = 0
        for _, spellID in ipairs(allSpells) do
            if addon:GetEventIDBySpellID(spellID) then count = count + 1 end
        end
        if brLog then brLog("[BossReminder] 点击首领 encounterId=%s 应显示 %d 行法术", tostring(encounterId), count)
        else print(string.format("[BossReminder] 点击首领 encounterId=%s 应显示 %d 行法术", tostring(encounterId), count)) end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() addon._RefreshSpellTable() end)
        else
            addon._RefreshSpellTable()
        end
        if addon._UpdateTabHighlight then addon._UpdateTabHighlight() end
    end)
    frame.btn:SetNormalFontObject((encounterId == state.selectedEncounterId) and "GameFontHighlight" or "GameFontNormal")
end

local function ResetBossRow(frame)
    if frame.btn then
        frame.btn.encounterId = nil
        frame.btn:SetText("")
    end
end

local function RefreshBossDataProvider()
    if not bossScrollView or not CreateDataProvider then return end
    local provider = CreateDataProvider()
    state.bosses = {}
    if not state.selectedInstanceId or not EnsureEncounterJournalLoaded() then
        bossScrollView:SetDataProvider(provider)
        if bossScrollBox and bossScrollBox.FullUpdate then pcall(bossScrollBox.FullUpdate, bossScrollBox) end
        return
    end
    EJ_SelectInstance(state.selectedInstanceId)
    local i = 1
    while true do
        local name, _, encounterId = EJ_GetEncounterInfoByIndex(i, state.selectedInstanceId)
        if not encounterId then break end
        state.bosses[#state.bosses + 1] = { name = name or ("Boss " .. i), encounterId = encounterId }
        provider:Insert({ name = name or ("Boss " .. i), encounterId = encounterId })
        i = i + 1
    end
    bossScrollView:SetDataProvider(provider)
    if bossScrollBox and bossScrollBox.FullUpdate then
        local mode = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or nil
        pcall(bossScrollBox.FullUpdate, bossScrollBox, mode)
    end
end

local function RefreshBossList()
    if useScrollBox and bossScrollView then
        RefreshBossDataProvider()
        return
    end
    if not bossContent then return end
    for _, f in ipairs(bossButtons) do f:Hide() f:SetParent(nil) end
    table.wipe(bossButtons)
    state.bosses = {}
    if not state.selectedInstanceId or not EnsureEncounterJournalLoaded() then bossContent:SetHeight(1) return end
    EJ_SelectInstance(state.selectedInstanceId)
    local y = 0
    local i = 1
    while true do
        local name, _, encounterId = EJ_GetEncounterInfoByIndex(i, state.selectedInstanceId)
        if not encounterId then break end
        state.bosses[#state.bosses + 1] = { name = name or ("Boss " .. i), encounterId = encounterId }
        local btn = CreateListButton(bossContent, name or tostring(encounterId), function()
            state.selectedEncounterId = encounterId
            local allSpells = GetEncounterSpells(encounterId)
            local count = 0
            for _, spellID in ipairs(allSpells) do
                if addon:GetEventIDBySpellID(spellID) then count = count + 1 end
            end
            if brLog then brLog("[BossReminder] 点击首领 encounterId=%s 应显示 %d 行法术", tostring(encounterId), count)
            else print(string.format("[BossReminder] 点击首领 encounterId=%s 应显示 %d 行法术", tostring(encounterId), count)) end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() addon._RefreshSpellTable() end)
            else
                addon._RefreshSpellTable()
            end
            if addon._UpdateTabHighlight then addon._UpdateTabHighlight() end
        end)
        btn.encounterId = encounterId
        btn:SetPoint("TOPLEFT", bossContent, "TOPLEFT", 0, -y)
        btn:SetPoint("RIGHT", bossContent, -20, 0)
        btn:Show()
        bossButtons[#bossButtons + 1] = btn
        y = y + 28
        i = i + 1
    end
    bossContent:SetHeight(math.max(y, 1))
end

local SPELL_ROW_HEIGHT = 28
local SPELL_HEADER_HEIGHT = 24
local spellDDCounter = 0

local function GetHighlightDurationSeconds()
    local v = GetCVar and GetCVar("encounterTimelineHighlightDuration")
    if v and v ~= "" then
        local n = tonumber(v)
        if n and n > 0 then return n / 1000 end  -- CVar 单位为 ms
    end
    return 5
end

local function CreateSpellTableHeader(parent)
    if spellHeaderFrame then return spellHeaderFrame end
    spellHeaderFrame = CreateFrame("Frame", nil, parent)
    spellHeaderFrame:SetHeight(SPELL_HEADER_HEIGHT)
    spellHeaderFrame:SetPoint("TOPLEFT", parent)
    spellHeaderFrame:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    spellHeaderFrame.cells = {}
    spellHeaderFrame.spellLbl = spellHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellHeaderFrame.spellLbl:SetPoint("LEFT", spellHeaderFrame, "LEFT", 0, 0)
    spellHeaderFrame.spellLbl:SetText(L.HEADER_SPELL or "技能")
    spellHeaderFrame.cells[1] = spellHeaderFrame.spellLbl
    local triggerHeaders = {
        { key = "trigger0", text = L.HEADER_TRIGGER0 or "Trigger0", tooltipKey = "TOOLTIP_TRIGGER0" },
        { key = "trigger1", text = L.HEADER_TRIGGER1 or "Trigger1", tooltipKey = "TOOLTIP_TRIGGER1" },
        { key = "trigger2", text = L.HEADER_TRIGGER2 or "Trigger2", tooltipKey = "TOOLTIP_TRIGGER2_FMT", useCVar = true },
    }
    for i, t in ipairs(triggerHeaders) do
        local lbl = spellHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetText(t.text)
        spellHeaderFrame.cells[i + 1] = lbl
        lbl:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(lbl, "ANCHOR_TOP")
                local tt
                if t.useCVar then
                    tt = (L[t.tooltipKey] or "Trigger to be activated when an encounter event reaches its 'highlight' duration on the timeline (typically, ~%ss before the cast is due)."):format(GetHighlightDurationSeconds())
                else
                    tt = L[t.tooltipKey] or ""
                end
                GameTooltip:SetText(tt)
                GameTooltip:Show()
            end
        end)
        lbl:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        lbl:EnableMouse(true)
    end
    spellHeaderFrame:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth() or 400
        local x = 0
        self.spellLbl:ClearAllPoints()
        self.spellLbl:SetPoint("LEFT", self, "LEFT", 0, 0)
        self.spellLbl:SetWidth(w * 0.25)
        x = w * 0.25
        for j = 2, 4 do
            local cell = self.cells[j]
            if cell then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", self, "LEFT", x, 0)
                cell:SetWidth(w * 0.18 - 4)
                x = x + w * 0.18
            end
        end
    end)
    return spellHeaderFrame
end

local function ApplySpellRowLayout(row)
    if not row.nameCell or not row.dds then return end
    local w = row:GetWidth() or 400
    row.nameCell:SetWidth(w * 0.25)
    -- 下拉框各 0.18，留出清空按钮区（60px + 16px 间距 + 8px 右边距）
    local ddW = 0.18
    local x = w * 0.25
    for j, col in ipairs({ { w = ddW }, { w = ddW }, { w = ddW } }) do
        local dd = row.dds[j]
        if dd then
            dd:ClearAllPoints()
            dd:SetPoint("TOPLEFT", row, "TOPLEFT", x, -3)
            dd:SetSize(math.max(w * col.w - 4, 60), 24)
            UIDropDownMenu_SetWidth(dd, math.max(w * col.w - 24, 50))
            x = x + w * col.w
        end
    end
    row.clearBtn:ClearAllPoints()
    row.clearBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
end

local function CreateSpellRowWidgets(row)
    if row.nameCell then return end
    row:SetHeight(SPELL_ROW_HEIGHT)
    row.nameCell = CreateFrame("Frame", nil, row)
    row.nameCell:SetPoint("TOPLEFT", row)
    row.nameCell:SetPoint("BOTTOMLEFT", row)
    row.nameCell:SetClipsChildren(true)
    row.icon = row.nameCell:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row.nameCell, "LEFT", 0, 0)
    row.nameLbl = row.nameCell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameLbl:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    row.nameLbl:SetPoint("RIGHT", row.nameCell, "RIGHT", -2, 0)
    row.nameLbl:SetWordWrap(false)
    row.dds = {}
    for j = 1, 3 do
        spellDDCounter = spellDDCounter + 1
        local dd = CreateFrame("Button", "BRSpellDD" .. spellDDCounter, row, "UIDropDownMenuTemplate")
        row.dds[j] = dd
    end
    row.clearBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.clearBtn:SetText(L.BUTTON_CLEAR or "清除")
    row.clearBtn:SetSize(60, 22)
    row:SetScript("OnSizeChanged", ApplySpellRowLayout)
end

local function InitSpellRow(row, elementData)
    CreateSpellRowWidgets(row)
    -- ScrollBox 元素需显式设置宽度；复用帧时 SetWidth 可能不触发 OnSizeChanged，故显式调用布局
    local w = (spellScrollBox and spellScrollBox:GetWidth()) or (row:GetParent() and row:GetParent():GetWidth()) or 450
    if w and w > 0 then row:SetWidth(w) end
    ApplySpellRowLayout(row)
    local spellID = elementData.spellID
    local spellName = elementData.spellName
    local cfg = elementData.cfg or {}
    local soundList = addon.GetBRSoundList and addon.GetBRSoundList() or { [SOUND_NONE_KEY] = L.NONE or "None" }
    local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or (GetSpellTexture and GetSpellTexture(spellID))
    row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.nameLbl:SetText(spellName or tostring(spellID))
    row.nameLbl:SetScript("OnEnter", function() if GameTooltip then GameTooltip:SetOwner(row, "ANCHOR_TOP") GameTooltip:SetSpellByID(spellID) GameTooltip:Show() end end)
    row.nameLbl:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.icon:SetScript("OnEnter", row.nameLbl:GetScript("OnEnter"))
    row.icon:SetScript("OnLeave", row.nameLbl:GetScript("OnLeave"))
    local cols = { { key = "textSound" }, { key = "warningSound" }, { key = "highlightSound" } }
    for j, col in ipairs(cols) do
        local dd = row.dds[j]
        local val = (cfg[col.key] and cfg[col.key] ~= "") and cfg[col.key] or SOUND_NONE_KEY
        UIDropDownMenu_SetText(dd, soundList[val] or L.NONE or "None")
        local sid, ckey = spellID, col.key
        UIDropDownMenu_Initialize(dd, function(self, level)
            for k, v in pairs(soundList) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = v
                info.func = function()
                    UIDropDownMenu_SetText(dd, v)
                    UpdateSpellConfig(sid, ckey, k)
                    if k and k ~= SOUND_NONE_KEY then
                        local path = addon.GetSelectedSoundPath and addon.GetSelectedSoundPath(k)
                        if path and path ~= "" and PlaySoundFile then pcall(PlaySoundFile, path, "Master") end
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    row.clearBtn:SetScript("OnClick", function()
        ClearSpellConfig(spellID)
        addon._RefreshSpellTable()
    end)
end

local function ResetSpellRow(row)
    if row.nameLbl then row.nameLbl:SetText("") end
    if row.icon then row.icon:SetTexture(nil) end
    for _, dd in ipairs(row.dds or {}) do UIDropDownMenu_SetText(dd, "") end
end

local function UpdateSpellHeaderVisibility()
    local showHeader = not not state.selectedEncounterId
    if spellHeaderFrame then
        if showHeader then
            spellHeaderFrame:Show()
            if spellScrollBox then spellHeaderFrame:SetFrameLevel(spellScrollBox:GetFrameLevel() + 2) end
            if spellScrollBox then
                spellScrollBox:ClearAllPoints()
                spellScrollBox:SetPoint("TOPLEFT", spellHeaderFrame, "BOTTOMLEFT", 0, -4)
                spellScrollBox:SetPoint("BOTTOMRIGHT", spellHeaderFrame:GetParent(), "BOTTOMRIGHT", -20, 0)
            end
            if spellScroll then
                spellScroll:ClearAllPoints()
                spellScroll:SetPoint("TOPLEFT", spellHeaderFrame, "BOTTOMLEFT", 0, -4)
                spellScroll:SetPoint("RIGHT", spellHeaderFrame:GetParent())
                spellScroll:SetPoint("BOTTOM", spellHeaderFrame:GetParent())
            end
        else
            spellHeaderFrame:Hide()
            local rightCol = spellHeaderFrame and spellHeaderFrame:GetParent()
            if rightCol then
                if spellScrollBox then
                    spellScrollBox:ClearAllPoints()
                    spellScrollBox:SetPoint("TOPLEFT", rightCol)
                    spellScrollBox:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", -20, 0)
                end
                if spellScroll then
                    spellScroll:ClearAllPoints()
                    spellScroll:SetPoint("TOPLEFT", rightCol)
                    spellScroll:SetPoint("RIGHT", rightCol)
                    spellScroll:SetPoint("BOTTOM", rightCol)
                end
            end
        end
    end
end

local function RefreshSpellDataProvider()
    if not spellScrollView or not CreateDataProvider then return end
    UpdateSpellHeaderVisibility()
    local provider = CreateDataProvider()
    state.spells = {}
    if not state.selectedEncounterId then
        spellScrollView:SetDataProvider(provider)
        if spellScrollBox and spellScrollBox.FullUpdate then pcall(spellScrollBox.FullUpdate, spellScrollBox) end
        return
    end
    local allSpells = GetEncounterSpells(state.selectedEncounterId)
    local spellsTable = (addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells()) or {}
    for _, spellID in ipairs(allSpells) do
        if addon:GetEventIDBySpellID(spellID) then
            state.spells[#state.spells + 1] = spellID
            local cfg = spellsTable[spellID] or {}
            provider:Insert({ spellID = spellID, spellName = ResolveSpellName(spellID) or tostring(spellID), cfg = cfg })
        end
    end
    spellScrollView:SetDataProvider(provider)
    if spellScrollBox and spellScrollBox.FullUpdate then
        local mode = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or nil
        pcall(spellScrollBox.FullUpdate, spellScrollBox, mode)
    end
end

local function RefreshSpellTable()
    if useScrollBox and spellScrollView then
        RefreshSpellDataProvider()
        return
    end
    UpdateSpellHeaderVisibility()
    if not spellContent then return end
    for _, row in ipairs(spellRows) do
        for _, c in ipairs(row) do c:Hide() c:SetParent(nil) end
    end
    table.wipe(spellRows)
    state.spells = {}
    if not state.selectedEncounterId then spellContent:SetHeight(1) return end
    local allSpells = GetEncounterSpells(state.selectedEncounterId)
    for _, spellID in ipairs(allSpells) do
        if addon:GetEventIDBySpellID(spellID) then state.spells[#state.spells + 1] = spellID end
    end
    local soundList = addon.GetBRSoundList and addon.GetBRSoundList() or { [SOUND_NONE_KEY] = L.NONE or "None" }
    local spellsTable = (addon.GetCurrentSpecSpells and addon:GetCurrentSpecSpells()) or {}
    local scrollW = spellScroll and spellScroll:GetWidth() or 400
    local contentW = scrollW - 24
    spellContent:SetWidth(contentW)
    local ddCounter = 0
    local y = 0
    for _, spellID in ipairs(state.spells) do
        local cfg = spellsTable[spellID] or {}
        local spellName = ResolveSpellName(spellID) or tostring(spellID)
        local row = {}
        local nameCellW = contentW * 0.25
        local nameCell = CreateFrame("Frame", nil, spellContent)
        nameCell:SetPoint("TOPLEFT", spellContent, "TOPLEFT", 0, -y)
        nameCell:SetSize(nameCellW, 28)
        nameCell:SetClipsChildren(true)
        local icon = nameCell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", nameCell, "LEFT", 0, 0)
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or (GetSpellTexture and GetSpellTexture(spellID))
        icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local nameLbl = nameCell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLbl:SetText(spellName)
        nameLbl:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        nameLbl:SetPoint("RIGHT", nameCell, "RIGHT", -2, 0)
        nameLbl:SetWordWrap(false)
        nameLbl:SetScript("OnEnter", function() if GameTooltip then GameTooltip:SetOwner(nameCell, "ANCHOR_TOP") GameTooltip:SetSpellByID(spellID) GameTooltip:Show() end end)
        nameLbl:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        nameLbl:EnableMouse(true)
        icon:SetScript("OnEnter", nameLbl:GetScript("OnEnter"))
        icon:SetScript("OnLeave", nameLbl:GetScript("OnLeave"))
        icon:EnableMouse(true)
        row[#row + 1] = nameCell
        local ddW = 0.18
        local x = contentW * 0.25
        for _, col in ipairs({ { key = "textSound", w = ddW }, { key = "warningSound", w = ddW }, { key = "highlightSound", w = ddW } }) do
            ddCounter = ddCounter + 1
            local dd = CreateFrame("Button", "BRSpellDD" .. ddCounter, spellContent, "UIDropDownMenuTemplate")
            dd:SetPoint("TOPLEFT", spellContent, "TOPLEFT", x, -y)
            dd:SetSize(math.max(contentW * col.w - 4, 60), 24)
            UIDropDownMenu_SetWidth(dd, math.max(contentW * col.w - 24, 50))
            local val = (cfg[col.key] and cfg[col.key] ~= "") and cfg[col.key] or SOUND_NONE_KEY
            UIDropDownMenu_SetText(dd, soundList[val] or L.NONE or "None")
            local sid, ckey = spellID, col.key
            UIDropDownMenu_Initialize(dd, function(self, level)
                for k, v in pairs(soundList) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = v
                    info.func = function()
                        UIDropDownMenu_SetText(dd, v)
                        UpdateSpellConfig(sid, ckey, k)
                        if k and k ~= SOUND_NONE_KEY then
                            local path = addon.GetSelectedSoundPath and addon.GetSelectedSoundPath(k)
                            if path and path ~= "" and PlaySoundFile then pcall(PlaySoundFile, path, "Master") end
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            row[#row + 1] = dd
            x = x + contentW * col.w
        end
        local clearBtn = CreateFrame("Button", nil, spellContent, "UIPanelButtonTemplate")
        clearBtn:SetText(L.BUTTON_CLEAR or "清除")
        clearBtn:SetSize(60, 22)
        clearBtn:SetPoint("TOPRIGHT", spellContent, "TOPRIGHT", -8, -y)
        clearBtn:SetScript("OnClick", function()
            ClearSpellConfig(spellID)
            addon._RefreshSpellTable()
        end)
        row[#row + 1] = clearBtn
        for _, c in ipairs(row) do c:Show() end
        spellRows[#spellRows + 1] = row
        y = y + 28
    end
    spellContent:SetHeight(math.max(y, 1))
end

addon._RefreshBossList = RefreshBossList
addon._RefreshSpellTable = RefreshSpellTable

local function BuildMainWindow()
    if mainFrame then
        mainFrame:Show()
        mainFrame:Raise()
        RefreshInstanceList()
        RefreshBossList()
        RefreshSpellTable()
        return
    end

    mainFrame = CreateFrame("Frame", "BossReminderMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(900, 580)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, 1)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText(L.OVERVIEW_TITLE or "BossReminder")

    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    local function UpdateTabHighlight()
        if seasonDungeonTab then
            seasonDungeonTab:SetNormalFontObject((state.mode == "season_dungeon") and "GameFontHighlight" or "GameFontNormal")
        end
        if buildDungeonTab then
            buildDungeonTab:SetNormalFontObject((state.mode == "build_dungeon") and "GameFontHighlight" or "GameFontNormal")
        end
        if buildRaidTab then
            buildRaidTab:SetNormalFontObject((state.mode == "build_raid") and "GameFontHighlight" or "GameFontNormal")
        end
        for _, btn in ipairs(instanceButtons) do
            btn:SetNormalFontObject((btn.instId == state.selectedInstanceId) and "GameFontHighlight" or "GameFontNormal")
        end
        if useScrollBox and bossScrollBox and bossScrollBox.FullUpdate then
            pcall(bossScrollBox.FullUpdate, bossScrollBox)
        else
            for _, btn in ipairs(bossButtons) do
                btn:SetNormalFontObject((btn.encounterId == state.selectedEncounterId) and "GameFontHighlight" or "GameFontNormal")
            end
        end
    end

    local function setMode(mode)
        state.mode = mode
        state.selectedInstanceId = nil
        state.selectedEncounterId = nil
        RefreshInstanceList()
        RefreshBossList()
        RefreshSpellTable()
        UpdateTabHighlight()
    end
    addon._UpdateTabHighlight = UpdateTabHighlight

    seasonDungeonTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    seasonDungeonTab:SetText("当前赛季地下城")
    seasonDungeonTab:SetSize(120, 28)
    seasonDungeonTab:SetPoint("TOPLEFT", 20, -50)
    seasonDungeonTab:SetScript("OnClick", function() setMode("season_dungeon") end)

    buildDungeonTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    buildDungeonTab:SetText("当前版本地下城")
    buildDungeonTab:SetSize(120, 28)
    buildDungeonTab:SetPoint("TOPLEFT", 148, -50)
    buildDungeonTab:SetScript("OnClick", function() setMode("build_dungeon") end)

    buildRaidTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    buildRaidTab:SetText("当前版本团本")
    buildRaidTab:SetSize(120, 28)
    buildRaidTab:SetPoint("TOPLEFT", 276, -50)
    buildRaidTab:SetScript("OnClick", function() setMode("build_raid") end)

    local instanceRow = CreateFrame("Frame", nil, mainFrame)
    instanceRow:SetPoint("TOPLEFT", 20, -85)
    instanceRow:SetPoint("RIGHT", -20, 0)
    instanceRow:SetHeight(40)

    instanceScroll, instanceContent = CreateHorizontalScrollFrame(instanceRow, "BRInstance")
    instanceScroll:SetPoint("TOPLEFT", instanceRow)
    instanceScroll:SetPoint("RIGHT", instanceRow)
    instanceScroll:SetHeight(28)
    instanceScrollBar = CreateFrame("Slider", nil, instanceRow)
    instanceScrollBar:SetOrientation("HORIZONTAL")
    instanceScrollBar:SetPoint("TOPLEFT", instanceScroll, "BOTTOMLEFT", 0, -2)
    instanceScrollBar:SetPoint("RIGHT", instanceRow, "RIGHT", 0, 0)
    instanceScrollBar:SetHeight(8)
    instanceScrollBar:SetMinMaxValues(0, 1)
    instanceScrollBar:SetValue(0)
    instanceScrollBar:SetScript("OnValueChanged", function(self, value)
        if instanceScroll then instanceScroll:SetHorizontalScroll(value) end
    end)
    instanceScroll.scrollBar = instanceScrollBar
    instanceScrollBar:Hide()

    local bodyArea = CreateFrame("Frame", nil, mainFrame)
    bodyArea:SetPoint("TOPLEFT", 20, -125)
    bodyArea:SetPoint("BOTTOMRIGHT", -20, 20)

    local leftCol = CreateFrame("Frame", nil, bodyArea)
    leftCol:SetPoint("TOPLEFT", bodyArea)
    leftCol:SetPoint("BOTTOMLEFT", bodyArea)
    leftCol:SetWidth(200)

    if CanUseScrollBox() then
        bossScrollBox = CreateFrame("Frame", nil, leftCol, "WowScrollBoxList")
        bossScrollBox:SetPoint("TOPLEFT", leftCol)
        bossScrollBox:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -20, 0)
        bossScrollBar = CreateFrame("EventFrame", nil, leftCol, "MinimalScrollBar")
        bossScrollBar:SetPoint("TOPLEFT", bossScrollBox, "TOPRIGHT", 4, 0)
        bossScrollBar:SetPoint("BOTTOMLEFT", bossScrollBox, "BOTTOMRIGHT", 4, 0)
        if bossScrollBar.SetHideIfUnscrollable then bossScrollBar:SetHideIfUnscrollable(true) end
        bossScrollView = CreateScrollBoxListLinearView()
        bossScrollView:SetElementExtent(BOSS_ROW_HEIGHT)
        bossScrollView:SetElementInitializer("Frame", InitBossRow)
        if bossScrollView.SetElementResetter then bossScrollView:SetElementResetter(ResetBossRow) end
        ScrollUtil.InitScrollBoxListWithScrollBar(bossScrollBox, bossScrollBar, bossScrollView)
        if ScrollUtil.AddManagedScrollBarVisibilityBehavior and CreateAnchor then
            ScrollUtil.AddManagedScrollBarVisibilityBehavior(bossScrollBox, bossScrollBar,
                { CreateAnchor("TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", bossScrollBar, -4, 0) },
                { CreateAnchor("TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", 0, 0) })
        end
    else
        bossScroll, bossContent = CreateScrollFrame(leftCol, "BRBoss")
        bossScroll:SetPoint("TOPLEFT", leftCol)
        bossScroll:SetPoint("RIGHT", leftCol)
        bossScroll:SetPoint("BOTTOM", leftCol)
    end

    local rightCol = CreateFrame("Frame", nil, bodyArea)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 10, 0)
    rightCol:SetPoint("BOTTOMRIGHT", bodyArea)

    spellHeaderFrame = CreateSpellTableHeader(rightCol)
    spellHeaderFrame:SetPoint("TOPLEFT", rightCol)
    spellHeaderFrame:SetPoint("RIGHT", rightCol, "RIGHT", -20, 0)
    spellHeaderFrame:Hide()

    if useScrollBox then
        spellScrollBox = CreateFrame("Frame", nil, rightCol, "WowScrollBoxList")
        spellScrollBox:SetPoint("TOPLEFT", rightCol)
        spellScrollBox:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", -20, 0)
        spellScrollBar = CreateFrame("EventFrame", nil, rightCol, "MinimalScrollBar")
        spellScrollBar:SetPoint("TOPLEFT", spellScrollBox, "TOPRIGHT", 4, 0)
        spellScrollBar:SetPoint("BOTTOMLEFT", spellScrollBox, "BOTTOMRIGHT", 4, 0)
        if spellScrollBar.SetHideIfUnscrollable then spellScrollBar:SetHideIfUnscrollable(true) end
        spellScrollView = CreateScrollBoxListLinearView()
        spellScrollView:SetElementExtent(SPELL_ROW_HEIGHT)
        spellScrollView:SetElementInitializer("Frame", InitSpellRow)
        if spellScrollView.SetElementResetter then spellScrollView:SetElementResetter(ResetSpellRow) end
        ScrollUtil.InitScrollBoxListWithScrollBar(spellScrollBox, spellScrollBar, spellScrollView)
        if ScrollUtil.AddManagedScrollBarVisibilityBehavior and CreateAnchor then
            ScrollUtil.AddManagedScrollBarVisibilityBehavior(spellScrollBox, spellScrollBar,
                { CreateAnchor("TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", spellScrollBar, -4, 0) },
                { CreateAnchor("TOPLEFT", 0, 0), CreateAnchor("BOTTOMRIGHT", 0, 0) })
        end
    else
        spellScroll, spellContent = CreateScrollFrame(rightCol, "BRSpell")
        spellScroll:SetPoint("TOPLEFT", rightCol)
        spellScroll:SetPoint("RIGHT", rightCol)
        spellScroll:SetPoint("BOTTOM", rightCol)
    end

    local settingsBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    settingsBtn:SetText(L.BUTTON_SETTINGS or "设置")
    settingsBtn:SetSize(60, 22)
    settingsBtn:SetPoint("TOPRIGHT", -60, -50)
    settingsBtn:SetScript("OnClick", function() if addon.OpenSettings then addon.OpenSettings() end end)

    mainFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    -- 首次显示后延迟刷新法术表，确保 ScrollBox 布局完成后再渲染
    mainFrame:SetScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if addon._RefreshSpellTable then addon._RefreshSpellTable() end end)
        end
    end)

    state.mode = "season_dungeon"
    state.selectedInstanceId = nil
    state.selectedEncounterId = nil
    RefreshInstanceList()
    RefreshBossList()
    RefreshSpellTable()
    UpdateTabHighlight()
end

function addon.OpenUI()
    BuildMainWindow()
    mainFrame:Show()
    mainFrame:Raise()
end

addon.OpenConfig = addon.OpenUI

function addon.DumpInstanceList()
    EnsureEncounterJournalLoaded()
    local season = GetCurrentSeason()
    if addon.SeasonInstances then
        local maxS = 0
        for s in pairs(addon.SeasonInstances) do if type(s) == "number" and s > maxS then maxS = s end end
        if not season or not addon.SeasonInstances[season] then season = maxS > 0 and maxS or nil end
    end
    local seasonDungeon = addon.GetInstance and addon.GetInstance(season, false) or {}
    local buildDungeon = addon.GetInstanceByBuildVersion and addon.GetInstanceByBuildVersion(nil, false) or {}
    local buildRaid = addon.GetInstanceByBuildVersion and addon.GetInstanceByBuildVersion(nil, true) or {}
    print(string.format("[BossReminder] season=%s 赛季地下城=%d | exp=%s 版本地下城=%d 版本团本=%d", tostring(season), #seasonDungeon, tostring(LE_EXPANSION_LEVEL_CURRENT), #buildDungeon, #buildRaid))
    for i, id in ipairs(seasonDungeon) do print("  season_dungeon", i, id, EJ_GetInstanceInfo and EJ_GetInstanceInfo(id)) end
    for i, id in ipairs(buildDungeon) do print("  build_dungeon", i, id, EJ_GetInstanceInfo and EJ_GetInstanceInfo(id)) end
    for i, id in ipairs(buildRaid) do print("  build_raid", i, id, EJ_GetInstanceInfo and EJ_GetInstanceInfo(id)) end
end

function addon.DumpInstanceSpells()
    local count = 0
    local lines = {}
    for encId, spells in pairs(encounterSpellCache) do
        count = count + 1
        local spellCount = type(spells) == "table" and #spells or 0
        local spellIds = {}
        if type(spells) == "table" then
            for i = 1, math.min(5, #spells) do spellIds[#spellIds + 1] = tostring(spells[i]) end
            if #spells > 5 then spellIds[#spellIds + 1] = "..." end
        end
        table.insert(lines, string.format("encounterID=%d, spells=%d [%s]", encId, spellCount, table.concat(spellIds, ",")))
    end
    print(string.format("[BossReminder] instance spell cache: %d encounters", count))
    table.sort(lines)
    for _, line in ipairs(lines) do print("  " .. line) end
end

local preloadFrame = CreateFrame("Frame")
preloadFrame:RegisterEvent("PLAYER_LOGIN")
preloadFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        preloadFrame:UnregisterEvent("PLAYER_LOGIN")
        C_Timer.After(2, PreloadInstanceSpells)
    end
end)
