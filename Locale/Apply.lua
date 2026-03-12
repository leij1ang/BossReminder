local addonName = ...
local ns = _G[addonName] or _G.BossReminder
local aceLocale = LibStub and LibStub("AceLocale-3.0", true)
if aceLocale and ns then
    local L = aceLocale:GetLocale(addonName, true)
    if L then
        ns.L = L
        return
    end
end
if ns then
    ns.L = setmetatable({}, { __index = function(_, key) return key end })
end
