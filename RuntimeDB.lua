local _, ns = ...

-- Runtime database class
local RuntimeDB = {}
RuntimeDB.__index = RuntimeDB

function RuntimeDB:new()
    local self = setmetatable({}, RuntimeDB)
    self.spellEventMap = {}  -- spellID -> eventID mapping
    self.spellConfigs = {}   -- spellID -> config cache
    return self
end

-- spellEventMap related methods
function RuntimeDB:setSpellEventMap(map)
    self.spellEventMap = map
end

function RuntimeDB:getSpellEventMap()
    return self.spellEventMap
end

function RuntimeDB:getEventIDBySpellID(spellID)
    return self.spellEventMap[spellID]
end

-- spellConfigs cache related methods
function RuntimeDB:cacheSpells(persistedSpells)
    self.spellConfigs = {}
    if type(persistedSpells) == "table" then
        for spellID, cfg in pairs(persistedSpells) do
            self.spellConfigs[spellID] = cfg
        end
    end
end

function RuntimeDB:getSpellConfig(spellID, createIfMissing)
    if not spellID then
        return nil
    end

    if not self.spellConfigs[spellID] and createIfMissing then
        self.spellConfigs[spellID] = {
            enabled = true,
            warningSound = "",
            highlightSound = "",
            shouldCountdown = false,
        }
    end

    if self.spellConfigs[spellID] and self.spellConfigs[spellID].enabled == nil then
        self.spellConfigs[spellID].enabled = true
    end

    return self.spellConfigs[spellID], spellID
end

function RuntimeDB:getAllSpellConfigs()
    return self.spellConfigs
end

function RuntimeDB:deleteSpellConfig(spellID)
    if spellID then
        self.spellConfigs[spellID] = nil
    end
end

function RuntimeDB:clearAllSpellConfigs()
    self.spellConfigs = {}
end

ns.RuntimeDB = RuntimeDB
ns.runtimeDB = RuntimeDB:new()
