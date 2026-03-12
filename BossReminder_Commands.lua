-- BossReminder_Commands: /pull, /break via AceConsole + optional DBM hook
local addon = _G.BossReminder
if not addon then return end

local runtime = { builtinCountdownActive = false }

local function StartBuiltinCountdown(seconds)
    if not C_PartyInfo or type(C_PartyInfo.DoCountdown) ~= "function" then return false end
    local ok = pcall(C_PartyInfo.DoCountdown, seconds)
    if ok then runtime.builtinCountdownActive = true return true end
    return false
end

local function StopBuiltinCountdown()
    if not runtime.builtinCountdownActive then return end
    if C_PartyInfo and type(C_PartyInfo.StopCountdown) == "function" then pcall(C_PartyInfo.StopCountdown) end
    runtime.builtinCountdownActive = false
end

local function ParsePositiveNumber(input, fallback)
    local n = tonumber((input or ""):match("%d+"))
    if n and n > 0 then return math.floor(n) end
    return fallback
end

local function HandlePullCommand(msg)
    StopBuiltinCountdown()
    StartBuiltinCountdown(math.max(1, math.floor(ParsePositiveNumber(msg, 10) or 10)))
end

local function HandleBreakCommand(msg)
    StopBuiltinCountdown()
    StartBuiltinCountdown(math.max(1, math.floor(ParsePositiveNumber(msg, 300) or 300)))
end

addon:RegisterChatCommand("brpull", function(msg) HandlePullCommand(msg) end)
addon:RegisterChatCommand("brbreak", function(msg) HandleBreakCommand(msg) end)

-- Hook DBM /pull and /break if present
local slashHookState = { pullWrapped = false, breakWrapped = false }
local function InstallDBMCommandSupport()
    local pullHandler = SlashCmdList and SlashCmdList["PULL"]
    if type(pullHandler) == "function" and not slashHookState.pullWrapped then
        SlashCmdList["PULL"] = function(msg, editBox) pullHandler(msg, editBox) HandlePullCommand(msg) end
        slashHookState.pullWrapped = true
    end
    local breakHandler = SlashCmdList and SlashCmdList["BREAK"]
    if type(breakHandler) == "function" and not slashHookState.breakWrapped then
        SlashCmdList["BREAK"] = function(msg, editBox) breakHandler(msg, editBox) HandleBreakCommand(msg) end
        slashHookState.breakWrapped = true
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEAVING_WORLD" then StopBuiltinCountdown() return end
    local loadedAddon = ...
    if loadedAddon == "BossReminder" or loadedAddon == "DBM-Core" then InstallDBMCommandSupport() end
end)
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DBM-Core") then InstallDBMCommandSupport() end
