-- ============================================================================
-- Shared Utilities
-- ============================================================================

local _, ns = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Remove leading and trailing spaces from string
function ns.TrimString(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Parse boolean string values
function ns.ParseTransferBoolean(value, defaultValue)
    local n = string.lower(ns.TrimString(value))
    if n == "1" or n == "true" or n == "yes" then return true end
    if n == "0" or n == "false" or n == "no" then return false end
    return defaultValue and true or false
end

-- Get audio path by LSM key
function ns.GetSelectedSoundPath(soundKey)
    if not soundKey or soundKey == "" then
        return nil
    end

    if not LSM then
        ns.TimelineLog("GetSelectedSoundPath: LSM not available for key=%s", tostring(soundKey))
        return nil
    end

    local path = LSM:Fetch("sound", soundKey, true)
    if path then
        return path
    end

    ns.TimelineLog("GetSelectedSoundPath: no match found for key=%s", tostring(soundKey))
    return nil
end

function ns.TimelineLog(fmt, ...)
    if not BossReminderDB or BossReminderDB.timelineLogs == false then
        return
    end
    print(string.format("|cffffff00[BossReminder]|r " .. fmt, ...))
end

-- Get LibSharedMedia instance (safe)
function ns.GetLSM()
    if not LibStub then
        return nil
    end
    return LibStub("LibSharedMedia-3.0", true)
end
