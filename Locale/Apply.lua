local addonName, ns = ...

local aceLocale = LibStub and LibStub("AceLocale-3.0", true)
if aceLocale then
    local L = aceLocale:GetLocale(addonName, true)
    if L then
        ns.L = L
        return
    end
end

-- Fallback when AceLocale failed to initialize.
ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
