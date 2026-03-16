
-- compatibility with deprecated function in TWW
local GetSpellInfo = GetSpellInfo or function(spellID)
   if not spellID then
      return nil
   end
   local spellInfo = C_Spell.GetSpellInfo(spellID)
   if spellInfo then
      return spellInfo.name, nil, spellInfo.iconID, spellInfo.castTime, spellInfo.minRange, spellInfo.maxRange, spellInfo.spellID, spellInfo.originalIconID
   end
end

local GetSpellName = GetSpellInfo or C_Spell.GetSpellName
local GetSpellIcon = GetSpellTexture or C_Spell.GetSpellTexture

local function headerShowTooltip(self)
   local parent = self:GetParent()
   if parent then
      local spellID = parent.spellID
      if spellID and spellID ~= 0 then
         local iconID = GetSpellIcon(spellID)
         GameTooltip:SetOwner(parent, "ANCHOR_RIGHT")
         GameTooltip:SetHyperlink("spell:"..spellID, EJ_GetDifficulty(), EJ_GetContentTuningID())
         if not C_AddOns.IsAddOnLoaded("idTip") then
            GameTooltip:AddDoubleLine("Spell ID", spellID)
            GameTooltip:AddDoubleLine("Icon ID", iconID)
         end
         GameTooltip:Show()
      end
   end
end

-- id holes in spell IDs to speed up scanning for private auras
local holes = {
   [474770] = 556604,
   [556606] = 936050,
   [936051] = 1049295,
   [1049296] = 1213133
}

local PA_IDS = {}
local PA_Names = {}
PA_IDS[410953] = true -- Volcanic Heart in EJ, but aura is Volcanic Heartbeat

local function ScanPrivateAuras()
   local id = 400000
   local misses = 0
   while misses < 80000 do
      id = id + 1
      if C_Spell.DoesSpellExist(id) then
         misses = 0
         if C_UnitAuras.AuraIsPrivate(id) then
            local name = C_Spell.GetSpellName(id)
            PA_Names[name] = true
            PA_IDS[id] = true
         end
      else
         misses = misses + 1
      end
      if holes and holes[id] then
         id = holes[id]
      end
   end
end

local function CheckPrivateAura(self)
   local parent = self:GetParent()
   if parent then
      local spellID = parent.spellID
      if spellID then
         --for _, iconFrame in ipairs(self.icons) do
         --   iconFrame.icon:SetTexture("Interface\\EncounterJournal\\UI-EJ-Icons") -- i was told this in not working properly on midnight
         --end
         local name = GetSpellName(spellID)
         if PA_IDS[spellID] or PA_Names[name] then
            local flags = C_EncounterJournal.GetSectionIconFlags(parent.myID)
            local index = ((flags and #flags) or 0) + 1
            local iconFrame = self.icons[index]
            iconFrame:Show()
            iconFrame.icon:SetTexture("Interface\\AddOns\\EncounterJournalSpellInfo\\nowa.tga")
            iconFrame.icon:SetTexCoord(0,1,0,1)
            iconFrame.tooltipTitle = "Private Aura"
            iconFrame.tooltipText = nil
         end
      end
   end
end

local f = CreateFrame("Frame")
local eventHandler = function(self, event, addon)
   if addon == "Blizzard_EncounterJournal" then
      C_Timer.After(1, function()
            -- scan for private auras
            ScanPrivateAuras()

            -- add spell tooltips and private aura icons
            hooksecurefunc(
               "EncounterJournal_ToggleHeaders",
               function()
                  for i = 1, 99 do
                     local frame = _G["EncounterJournalInfoHeader"..i.."HeaderButton"]
                     if frame then
                        frame:SetScript("OnEnter", headerShowTooltip)
                        frame:SetScript("OnLeave", GameTooltip_Hide)
                        CheckPrivateAura(frame)
                     end
                  end
               end
            )

            -- add encounterID on boss buttons
            do
               local function hookItem(self, button, data)
                  if data.bossID then
                     local encounterID, instanceID = select(7, EJ_GetEncounterInfo(data.bossID))
                     if encounterID then
                        if not button.encounterIDdisplay then
                           button.encounterIDdisplay = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                           button.encounterIDdisplay:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -10)
                           button.encounterIDdisplay:SetTextColor(0.65, 0.65, 0.65)
                        end
                        button.encounterIDdisplay:SetText(encounterID)
                        return
                     end
                  end
                  if button.encounterIDdisplay then
                     button.encounterIDdisplay:SetText("")
                  end
               end
               local scrollBox = EncounterJournalEncounterFrameInfo.BossesScrollBox
               local view = scrollBox:GetView()
               view:RegisterCallback(ScrollBoxListViewMixin.Event.OnAcquiredFrame, hookItem, scrollBox)
            end
      end)
      f:UnregisterEvent("ADDON_LOADED")
   end
end
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", eventHandler)
f:Show()
