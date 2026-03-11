local addonName, ns = ...

local runtime = {
    builtinCountdownActive = false,
}

local function StartBuiltinCountdown(seconds)
    if not C_PartyInfo or type(C_PartyInfo.DoCountdown) ~= "function" then
        return false
    end

    local ok = pcall(C_PartyInfo.DoCountdown, seconds)
    if ok then
        runtime.builtinCountdownActive = true
        return true
    end

    return false
end

local function StopBuiltinCountdown()
    if not runtime.builtinCountdownActive then
        return
    end

    if C_PartyInfo and type(C_PartyInfo.StopCountdown) == "function" then
        pcall(C_PartyInfo.StopCountdown)
    end

    runtime.builtinCountdownActive = false
end

local function StopExternalTimer()
    StopBuiltinCountdown()
end

local function ParsePositiveNumber(input, fallback)
    local n = tonumber((input or ""):match("%d+"))
    if n and n > 0 then
        return math.floor(n)
    end
    return fallback
end

local function StartPullTimer(seconds)
    StopExternalTimer()

    local remain = math.max(1, math.floor(seconds or 10))
    StartBuiltinCountdown(remain)
end

local function StartBreakTimer(seconds)
    StopExternalTimer()

    local totalSeconds = math.max(1, math.floor(seconds or 300))
    StartBuiltinCountdown(totalSeconds)
end

local function HandlePullCommand(msg)
    local seconds = ParsePositiveNumber(msg, 10)
    StartPullTimer(seconds)
end

local function HandleBreakCommand(msg)
    local seconds = ParsePositiveNumber(msg, 300)
    StartBreakTimer(seconds)
end

local slashHookState = {
    pullWrapped = false,
    breakWrapped = false,
    pullRegistered = false,
    breakRegistered = false,
}

local function InstallDBMCommandSupport()
    local pullHandler = SlashCmdList and SlashCmdList["PULL"] or nil
    if type(pullHandler) == "function" and not slashHookState.pullWrapped then
        SlashCmdList["PULL"] = function(msg, editBox)
            pullHandler(msg, editBox)
            HandlePullCommand(msg)
        end
        slashHookState.pullWrapped = true
    elseif type(pullHandler) ~= "function" and not slashHookState.pullRegistered then
        SLASH_BRP_PULL1 = "/pull"
        SlashCmdList["BRP_PULL"] = function(msg)
            HandlePullCommand(msg)
        end
        slashHookState.pullRegistered = true
    end

    local breakHandler = SlashCmdList and SlashCmdList["BREAK"] or nil
    if type(breakHandler) == "function" and not slashHookState.breakWrapped then
        SlashCmdList["BREAK"] = function(msg, editBox)
            breakHandler(msg, editBox)
            HandleBreakCommand(msg)
        end
        slashHookState.breakWrapped = true
    elseif type(breakHandler) ~= "function" and not slashHookState.breakRegistered then
        SLASH_BRP_BREAK1 = "/break"
        SlashCmdList["BRP_BREAK"] = function(msg)
            HandleBreakCommand(msg)
        end
        slashHookState.breakRegistered = true
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEAVING_WORLD" then
        StopExternalTimer()
        return
    end

    local loadedAddon = ...
    if loadedAddon == addonName or loadedAddon == "DBM-Core" then
        InstallDBMCommandSupport()
    end
end)

if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DBM-Core") then
    InstallDBMCommandSupport()
end
