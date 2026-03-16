-- season.lua: 赛季/BuildVersion -> 地下城/团本 instanceID 映射，手动维护
-- SeasonInstances: key=赛季号(如15)，用于 M+ 赛季
-- BuildVersionInstances: key=LE_EXPANSION_LEVEL_CURRENT，按资料片匹配
local addon = _G.BossReminder
if not addon then return end

addon.BuildVersionInstances = {
    [10] = { -- LE_EXPANSION_WAR_WITHIN (TWW)
        dungeon = { 1309,1304,1311,1316,1313,1315,1299,1300 },
        mythic = { 1316,1300,1299,1315 },
        raid = { 1314, 1312,1307,1308 },
    },
    [11] = { -- LE_EXPANSION_MIDNIGHT
        dungeon = { 1309,1304,1311,1316,1313,1315,1299,1300 },
        raid = { 1314, 1312,1307,1308 },
    },
}

addon.SeasonInstances = {
    [15] = {
        dungeon = { 1316,1300,1299,1315 },
    },
}

local function collectInstances(data, key)
    if not data or type(data) ~= "table" then return {} end
    local list = data[key]
    if type(list) ~= "table" then return {} end
    local out = {}
    for _, instId in ipairs(list) do
        if type(instId) == "number" and instId > 0 then out[#out + 1] = instId end
    end
    table.sort(out)
    return out
end

function addon.GetInstance(season, isRaid)
    if not season then return {} end
    local data = addon.SeasonInstances and addon.SeasonInstances[season]
    return collectInstances(data, isRaid and "raid" or "dungeon")
end

function addon.GetInstanceByBuildVersion(expLevel, isRaid)
    if expLevel == nil then expLevel = LE_EXPANSION_LEVEL_CURRENT end
    local data = addon.BuildVersionInstances and addon.BuildVersionInstances[expLevel]
    return collectInstances(data, isRaid and "raid" or "dungeon")
end
