-- BossReminder_Tools: /brtools window, fully native UI
local addon = _G.BossReminder
if not addon then return end

local toolsFrame, contentFrame, headerFrame, listFrame, statusText, refreshButton
local scrollBox, scrollBar, scrollView, resizeButton
local headerCells = {}
local toolsData = {}
local resizeRefreshPending = false

local ROW_HEIGHT = 22
local WINDOW_MIN_WIDTH = 820
local WINDOW_MIN_HEIGHT = 420

-- 与 BossReminder_Sound 一致：使用命名枚举，这样配置的「警告音」「高亮/倒数」会正确显示
local EncounterEventSoundTrigger = Enum.EncounterEventSoundTrigger
local SOUND_TRIGGER_WARNING  = EncounterEventSoundTrigger.OnTimelineEventFinished
local SOUND_TRIGGER_HIGHLIGHT = EncounterEventSoundTrigger.OnTimelineEventHighlight
local SOUND_TRIGGER_EXTRA = nil
do
    for name, value in pairs(EncounterEventSoundTrigger) do
        if value ~= SOUND_TRIGGER_WARNING and value ~= SOUND_TRIGGER_HIGHLIGHT and type(value) == "number" then
            SOUND_TRIGGER_EXTRA = value
            break
        end
    end
end

local COLUMNS = {
    { key = "color", text = "Color", ratio = 0.09 },
    { key = "enabled", text = "On", ratio = 0.06 },
    { key = "eventID", text = "EventID", ratio = 0.10 },
    { key = "icons", text = "Icons", ratio = 0.19 },
    { key = "severity", text = "Severity", ratio = 0.11 },
    { key = "soundWarning", text = "Warning", ratio = 0.09 },
    { key = "soundHighlight", text = "Highlight", ratio = 0.09 },
    { key = "soundExtra", text = "S2", ratio = 0.06 },
    { key = "spell", text = "Spell", ratio = 0.21 },
}

local function ColorToHex(c)
    if not c then return "N/A" end
    local r = math.floor((c.r or 0) * 255 + 0.5)
    local g = math.floor((c.g or 0) * 255 + 0.5)
    local b = math.floor((c.b or 0) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x#%02X%02X%02X|r", r, g, b, r, g, b)
end

local function SeverityName(val)
    for name, v in pairs(Enum.EncounterEventSeverity) do
        if v == val then return name end
    end
    return tostring(val or "?")
end

local function IconmaskName(val)
    if val == 0 then return "0" end
    local parts = {}
    for name, v in pairs(Enum.EncounterEventIconmask) do
        if v ~= 0 and bit.band(val, v) == v then
            parts[#parts + 1] = name
        end
    end
    if #parts == 0 then return tostring(val) end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function ResolveSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if GetSpellInfo then
        local name = GetSpellInfo(spellID)
        if name and name ~= "" then return name end
    end
    return nil
end

local function GetEventSoundInfo(eventID, trigger)
    if not eventID then return nil end
    local ok, sound = pcall(C_EncounterEvents.GetEventSound, eventID, trigger)
    if not ok or not sound then return nil end
    return sound
end

local function BuildSoundLabel(sound)
    if type(sound) ~= "table" then return "-" end
    if sound.file and sound.file ~= "" then
        local leaf = tostring(sound.file):match("[^\\/]+$") or tostring(sound.file)
        leaf = leaf:gsub("%.%w+$", "")
        if #leaf > 12 then
            leaf = leaf:sub(1, 12) .. "..."
        end
        return leaf
    end
    if sound.soundKitID then
        return tostring(sound.soundKitID)
    end
    return "Play"
end

local function PlayEncounterSound(sound)
    if type(sound) ~= "table" then return false end
    if sound.file and sound.file ~= "" and PlaySoundFile then
        local ok = pcall(PlaySoundFile, sound.file, sound.channel or "Master")
        return ok
    end
    if sound.soundKitID and PlaySound then
        local ok = pcall(PlaySound, sound.soundKitID, sound.channel or "Master")
        return ok
    end
    return false
end

local function SetStatusText(text)
    if statusText then
        statusText:SetText(text or "")
    end
end

local function SetRefreshButtonBusy(isBusy)
    if not refreshButton then return end
    refreshButton:SetEnabled(not isBusy)
    refreshButton:SetText(isBusy and "Loading..." or "Reload Data")
end

local function ApplyColumnLayout(parent, regions)
    local width = math.max(parent:GetWidth() - 12, 1)
    local x = 6

    for index, column in ipairs(COLUMNS) do
        local region = regions[index]
        local cellWidth
        if index == #COLUMNS then
            cellWidth = width - x + 6
        else
            cellWidth = math.floor(width * column.ratio)
        end

        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -1)
        region:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 1)
        region:SetWidth(math.max(cellWidth, 1))
        x = x + cellWidth
    end
end

local function LayoutHeader()
    if not headerFrame or #headerCells == 0 then return end
    ApplyColumnLayout(headerFrame, headerCells)
end

local function CreateSoundButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetHeight(18)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button.soundData = nil
    button.eventID = nil
    button.triggerEnum = nil
    button:SetScript("OnClick", function(self)
        -- 优先用 EncounterEvents 自带的 PlayEventSound 播放（保证和实际战斗里效果一致）
        if self.eventID and self.triggerEnum then
            local ok = pcall(C_EncounterEvents.PlayEventSound, self.eventID, self.triggerEnum)
            if ok then
                SetStatusText("PlayEventSound")
                return
            end
        end
        -- 回退到直接播放 soundData（兼容没有 PlayEventSound 的版本）
        if self.soundData and PlayEncounterSound(self.soundData) then
            SetStatusText("Previewing encounter sound")
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(self.soundData) == "table" then
            GameTooltip:AddLine(self.triggerName or "Sound", 1, 0.82, 0)
            if self.soundData.file and self.soundData.file ~= "" then
                GameTooltip:AddLine(self.soundData.file, 0.9, 0.9, 0.9, true)
            end
            if self.soundData.soundKitID then
                GameTooltip:AddLine("SoundKitID: " .. tostring(self.soundData.soundKitID), 0.8, 0.8, 0.8)
            end
            if self.soundData.channel then
                GameTooltip:AddLine("Channel: " .. tostring(self.soundData.channel), 0.8, 0.8, 0.8)
            end
            GameTooltip:AddLine("Click to preview", 0.3, 1, 0.3)
        else
            GameTooltip:AddLine(self.triggerName or "Sound", 1, 0.82, 0)
            GameTooltip:AddLine("No sound", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return button
end

local function CreateRowWidgets(row)
    row:SetHeight(ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    local function CreateCell(fontObject, justify)
        local text = row:CreateFontString(nil, "ARTWORK", fontObject)
        text:SetJustifyH(justify or "LEFT")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(false)
        return text
    end

    row.colorText = CreateCell("GameFontHighlightSmall")
    row.enabledText = CreateCell("GameFontHighlightSmall", "CENTER")
    row.eventIDText = CreateCell("GameFontHighlightSmall")
    row.iconsText = CreateCell("GameFontHighlightSmall")
    row.severityText = CreateCell("GameFontHighlightSmall")
    row.soundWarningButton = CreateSoundButton(row)
    row.soundWarningButton.triggerName = "Warning"
    row.soundHighlightButton = CreateSoundButton(row)
    row.soundHighlightButton.triggerName = "Highlight"
    row.soundExtraButton = CreateSoundButton(row)
    row.soundExtraButton.triggerName = "S2"

    row.spellButton = CreateFrame("Button", nil, row)
    row.spellButton.icon = row.spellButton:CreateTexture(nil, "ARTWORK")
    row.spellButton.icon:SetSize(16, 16)
    row.spellButton.icon:SetPoint("LEFT", row.spellButton, "LEFT", 0, 0)

    row.spellButton.text = row.spellButton:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.spellButton.text:SetPoint("TOPLEFT", row.spellButton.icon, "TOPRIGHT", 4, 0)
    row.spellButton.text:SetPoint("BOTTOMRIGHT", row.spellButton, "BOTTOMRIGHT", 0, 0)
    row.spellButton.text:SetJustifyH("LEFT")
    row.spellButton.text:SetJustifyV("MIDDLE")
    row.spellButton.text:SetWordWrap(false)
    row.spellButton:SetScript("OnEnter", function(button)
        if not button.spellID or not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(button.spellID)
        GameTooltip:Show()
    end)
    row.spellButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row.cells = {
        row.colorText,
        row.enabledText,
        row.eventIDText,
        row.iconsText,
        row.severityText,
        row.soundWarningButton,
        row.soundHighlightButton,
        row.soundExtraButton,
        row.spellButton,
    }

    row:SetScript("OnSizeChanged", function(self)
        ApplyColumnLayout(self, self.cells)
    end)
    ApplyColumnLayout(row, row.cells)
end

local function UpdateRow(row, entry)
    if not row.cells then
        CreateRowWidgets(row)
    end

    if (entry.rowIndex or 1) % 2 == 0 then
        row.bg:SetColorTexture(1, 1, 1, 0.03)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end

    row.colorText:SetText(ColorToHex(entry.color))
    row.enabledText:SetText(entry.enabled and "|cff00ff00Y|r" or "|cffff0000N|r")
    row.eventIDText:SetText(tostring(entry.encounterEventID or ""))
    row.iconsText:SetText(IconmaskName(entry.icons))
    row.severityText:SetText(SeverityName(entry.severity))
    local eventIDForSound = entry.encounterEventID
    row.soundWarningButton.eventID = eventIDForSound
    row.soundWarningButton.triggerEnum = SOUND_TRIGGER_WARNING
    row.soundWarningButton.soundData = entry.soundWarning
    row.soundWarningButton:SetText(BuildSoundLabel(entry.soundWarning))
    row.soundWarningButton:SetEnabled(entry.soundWarning ~= nil)
    row.soundHighlightButton.eventID = eventIDForSound
    row.soundHighlightButton.triggerEnum = SOUND_TRIGGER_HIGHLIGHT
    row.soundHighlightButton.soundData = entry.soundHighlight
    row.soundHighlightButton:SetText(BuildSoundLabel(entry.soundHighlight))
    row.soundHighlightButton:SetEnabled(entry.soundHighlight ~= nil)
    row.soundExtraButton.eventID = eventIDForSound
    row.soundExtraButton.triggerEnum = SOUND_TRIGGER_EXTRA
    row.soundExtraButton.soundData = entry.soundExtra
    row.soundExtraButton:SetText(BuildSoundLabel(entry.soundExtra))
    row.soundExtraButton:SetEnabled(entry.soundExtra ~= nil)
    if entry.iconFileID then
        row.spellButton.icon:SetTexture(entry.iconFileID)
        row.spellButton.icon:Show()
        row.spellButton.text:ClearAllPoints()
        row.spellButton.text:SetPoint("TOPLEFT", row.spellButton.icon, "TOPRIGHT", 4, 0)
        row.spellButton.text:SetPoint("BOTTOMRIGHT", row.spellButton, "BOTTOMRIGHT", 0, 0)
    else
        row.spellButton.icon:SetTexture(nil)
        row.spellButton.icon:Hide()
        row.spellButton.text:ClearAllPoints()
        row.spellButton.text:SetAllPoints()
    end
    row.spellButton.text:SetText("|cff71d5ff" .. tostring(entry.spellName or entry.spellID or "") .. "|r")
    row.spellButton.spellID = entry.spellID
end

local function ResetRow(row)
    if row.spellButton then
        row.spellButton.spellID = nil
        row.spellButton.text:SetText("")
        row.spellButton.icon:SetTexture(nil)
        row.spellButton.icon:Hide()
    end
    if row.soundWarningButton then
        row.soundWarningButton.eventID = nil
        row.soundWarningButton.soundData = nil
        row.soundWarningButton:SetText("-")
        row.soundWarningButton:SetEnabled(false)
    end
    if row.soundHighlightButton then
        row.soundHighlightButton.eventID = nil
        row.soundHighlightButton.soundData = nil
        row.soundHighlightButton:SetText("-")
        row.soundHighlightButton:SetEnabled(false)
    end
    if row.soundExtraButton then
        row.soundExtraButton.eventID = nil
        row.soundExtraButton.soundData = nil
        row.soundExtraButton:SetText("-")
        row.soundExtraButton:SetEnabled(false)
    end
end

local function FullUpdateScrollBox()
    if not scrollBox or not scrollBox.FullUpdate then return end
    local updateMode = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or nil
    if updateMode ~= nil then
        pcall(scrollBox.FullUpdate, scrollBox, updateMode)
    else
        pcall(scrollBox.FullUpdate, scrollBox)
    end
end

local function RefreshDataProvider()
    if not scrollView or not CreateDataProvider then return end

    local provider = CreateDataProvider()
    for index, entry in ipairs(toolsData) do
        entry.rowIndex = index
        provider:Insert(entry)
    end

    scrollView:SetDataProvider(provider)
    FullUpdateScrollBox()
end

local function RequestScrollRefresh()
    if resizeRefreshPending then return end
    resizeRefreshPending = true
    C_Timer.After(0, function()
        resizeRefreshPending = false
        LayoutHeader()
        FullUpdateScrollBox()
    end)
end

local function SortToolsData()
    table.sort(toolsData, function(a, b)
        return (a.encounterEventID or 0) < (b.encounterEventID or 0)
    end)
end

local function BuildToolsDataFromCache()
    table.wipe(toolsData)
    local cache = addon.eventCache
    if not cache or type(cache) ~= "table" then
        return 0
    end
    local eventIDForSound = nil
    for eventID, info in pairs(cache) do
        if info then
            eventIDForSound = info.encounterEventID or eventID
            toolsData[#toolsData + 1] = {
                color = info.color,
                enabled = info.enabled,
                encounterEventID = eventIDForSound,
                iconFileID = info.iconFileID,
                icons = info.icons,
                severity = info.severity,
                spellID = info.spellID,
                spellName = ResolveSpellName(info.spellID),
                soundWarning = GetEventSoundInfo(eventIDForSound, SOUND_TRIGGER_WARNING),
                soundHighlight = GetEventSoundInfo(eventIDForSound, SOUND_TRIGGER_HIGHLIGHT),
                soundExtra = SOUND_TRIGGER_EXTRA ~= nil and GetEventSoundInfo(eventIDForSound, SOUND_TRIGGER_EXTRA) or nil,
            }
        end
    end
    return #toolsData
end

local function RefreshToolsDataAsync()
    SetRefreshButtonBusy(true)
    RefreshDataProvider()

    if addon.ScanAllEvents then
        addon:ScanAllEvents()
    end

    local cache = addon.eventCache
    if not cache or type(cache) ~= "table" then
        SetStatusText("Event cache unavailable (ScanAllEvents not run?)")
        SetRefreshButtonBusy(false)
        return
    end

    local n = BuildToolsDataFromCache()
    SortToolsData()
    RefreshDataProvider()
    SetStatusText(string.format("Loaded %d events (from cache)", n))
    SetRefreshButtonBusy(false)
end

local function BuildScrollArea(parent)
    if not CreateScrollBoxListLinearView or not ScrollUtil then
        SetStatusText("ScrollBox unavailable")
        return
    end

    listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -6)
    listFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)

    scrollBox = CreateFrame("Frame", nil, listFrame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -26, 0)

    scrollBar = CreateFrame("EventFrame", nil, listFrame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    if scrollBar.SetHideIfUnscrollable then
        scrollBar:SetHideIfUnscrollable(true)
    end

    scrollView = CreateScrollBoxListLinearView()
    scrollView:SetElementExtent(ROW_HEIGHT)
    scrollView:SetElementInitializer("Frame", function(frame, elementData)
        UpdateRow(frame, elementData)
    end)
    if scrollView.SetElementResetter then
        scrollView:SetElementResetter(function(frame)
            ResetRow(frame)
        end)
    end

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior and CreateAnchor then
        ScrollUtil.AddManagedScrollBarVisibilityBehavior(
            scrollBox,
            scrollBar,
            {
                CreateAnchor("TOPLEFT", 0, 0),
                CreateAnchor("BOTTOMRIGHT", scrollBar, -8, 0),
            },
            {
                CreateAnchor("TOPLEFT", 0, 0),
                CreateAnchor("BOTTOMRIGHT", 0, 0),
            }
        )
    end

    listFrame:SetScript("OnSizeChanged", RequestScrollRefresh)
end

local function BuildNativeWindow()
    toolsFrame = CreateFrame("Frame", "BossReminderToolsFrame", UIParent, "BasicFrameTemplateWithInset")
    toolsFrame:SetSize(960, 560)
    toolsFrame:SetPoint("CENTER")
    toolsFrame:SetClampedToScreen(true)
    toolsFrame:SetToplevel(true)
    toolsFrame:SetFrameStrata("DIALOG")
    toolsFrame:SetFrameLevel(20)
    toolsFrame:SetMovable(true)
    toolsFrame:EnableMouse(true)
    toolsFrame:RegisterForDrag("LeftButton")
    toolsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    toolsFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    toolsFrame:SetResizable(true)
    if toolsFrame.SetResizeBounds then
        toolsFrame:SetResizeBounds(WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT)
    elseif toolsFrame.SetMinResize then
        toolsFrame:SetMinResize(WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT)
    end
    toolsFrame:SetScript("OnSizeChanged", RequestScrollRefresh)
    toolsFrame:SetScript("OnShow", function()
        toolsFrame:Raise()
        RequestScrollRefresh()
    end)

    if toolsFrame.TitleText then
        toolsFrame.TitleText:SetText("BossReminder Tools - Encounter Events")
    end

    refreshButton = CreateFrame("Button", nil, toolsFrame, "UIPanelButtonTemplate")
    refreshButton:SetSize(72, 22)
    refreshButton:SetText("Reload Data")
    refreshButton:SetPoint("TOPRIGHT", toolsFrame, "TOPRIGHT", -34, -30)
    refreshButton:SetScript("OnClick", function()
        RefreshToolsDataAsync()
    end)

    resizeButton = CreateFrame("Button", nil, toolsFrame, "PanelResizeButtonTemplate")
    resizeButton:SetPoint("BOTTOMRIGHT", toolsFrame, "BOTTOMRIGHT", -3, 3)

    contentFrame = CreateFrame("Frame", nil, toolsFrame)
    contentFrame:SetPoint("TOPLEFT", toolsFrame.Inset or toolsFrame, "TOPLEFT", 8, -8)
    contentFrame:SetPoint("BOTTOMRIGHT", toolsFrame.Inset or toolsFrame, "BOTTOMRIGHT", -8, 8)

    statusText = contentFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    statusText:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -6, 0)
    statusText:SetHeight(18)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("MIDDLE")

    headerFrame = CreateFrame("Frame", nil, contentFrame)
    headerFrame:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -4)
    headerFrame:SetPoint("TOPRIGHT", statusText, "BOTTOMRIGHT", 0, -4)
    headerFrame:SetHeight(20)
    headerFrame:SetScript("OnSizeChanged", LayoutHeader)

    for _, column in ipairs(COLUMNS) do
        local cell = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        cell:SetText("|cffffd100" .. column.text .. "|r")
        cell:SetJustifyH(column.key == "enabled" and "CENTER" or "LEFT")
        cell:SetJustifyV("MIDDLE")
        cell:SetWordWrap(false)
        headerCells[#headerCells + 1] = cell
    end

    local divider = headerFrame:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -2)
    divider:SetHeight(1)

    BuildScrollArea(contentFrame)
    LayoutHeader()
    RefreshToolsDataAsync()
end

local function ToggleToolsWindow()
    if not toolsFrame then
        BuildNativeWindow()
        return
    end

    if toolsFrame:IsShown() then
        toolsFrame:Hide()
    else
        toolsFrame:Show()
        toolsFrame:Raise()
        RefreshToolsDataAsync()
    end
end

addon:RegisterChatCommand("brtools", function()
    ToggleToolsWindow()
end)
