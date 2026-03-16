-- Shared utilities; attach to BossReminder addon
local addon = _G.BossReminder
if not addon then return end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

function addon.TrimString(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function addon.ParseTransferBoolean(value, defaultValue)
    local n = string.lower(addon.TrimString(value))
    if n == "1" or n == "true" or n == "yes" then return true end
    if n == "0" or n == "false" or n == "no" then return false end
    return defaultValue and true or false
end

function addon.GetSelectedSoundPath(soundKey)
    if not soundKey or soundKey == "" then return nil end
    if not LSM then return nil end
    local path = LSM:Fetch("sound", soundKey, true)
    return path
end

function addon.brLog(fmt, ...)
    if not addon.db or not addon.db.profile then return end
    local s = addon.db.profile.settings
    if not s or type(s) ~= "table" or s.brLogEnabled ~= true then return end
    print(string.format("|cffffff00[BossReminder]|r " .. fmt, ...))
end

function addon.GetLSM()
    if not LibStub then return nil end
    return LibStub("LibSharedMedia-3.0", true)
end

addon.SOUND_NONE_KEY = "__none__"

function addon.GetBRSoundList()
    local L = addon.L or setmetatable({}, { __index = function(_, k) return k end })
    local list = { [addon.SOUND_NONE_KEY] = L.NONE or "None" }
    local lsm = addon.GetLSM()
    if lsm then
        local sounds = lsm:List("sound") or {}
        for _, displayName in ipairs(sounds) do
            local plain = displayName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if plain and plain:match("^BR") then
                list[plain] = displayName
                if displayName ~= plain then list[displayName] = displayName end
            end
        end
        local keys = {}
        for k in pairs(list) do if k ~= addon.SOUND_NONE_KEY then keys[#keys+1] = k end end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local ordered = { [addon.SOUND_NONE_KEY] = list[addon.SOUND_NONE_KEY] }
        for _, k in ipairs(keys) do ordered[k] = list[k] end
        return ordered
    end
    return list
end
