-- cbk-npc/shared/log.lua
-- Structured debug logging and perf markers for cbk-npc

CBKAI = CBKAI or {}

local M = {}

local function isTruthyConvar(name)
    local value = string.lower(GetConvar(name, 'false'))
    return value == 'true' or value == '1' or value == 'yes' or value == 'on'
end

local function isDebugEnabled()
    return isTruthyConvar('cbk_npc_debug')
        or (type(Config) == 'table' and type(Config.Advanced) == 'table' and Config.Advanced.debug == true)
end

local function isPerfEnabled()
    return isTruthyConvar('cbk_npc_perf') or isDebugEnabled()
end

local function formatMessage(message, ...)
    if select('#', ...) == 0 then
        return tostring(message)
    end

    local ok, formatted = pcall(string.format, tostring(message), ...)
    if ok then
        return formatted
    end

    local parts = { tostring(message) }
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end

    return table.concat(parts, ' ')
end

function M.debug(...)
    if isDebugEnabled() then
        print(('^5[CBK-NPC][DEBUG]^7 %s'):format(formatMessage(...)))
    end
end

function M.info(...)
    print(('^2[CBK-NPC][INFO]^7 %s'):format(formatMessage(...)))
end

function M.warn(...)
    print(('^3[CBK-NPC][WARN]^7 %s'):format(formatMessage(...)))
end

function M.error(...)
    print(('^1[CBK-NPC][ERROR]^7 %s'):format(formatMessage(...)))
end

-- Perf marker (simple)
function M.perfMarker(...)
    if not isPerfEnabled() then
        return
    end

    print(('^6[CBK-NPC][PERF]^7 %s @ %d'):format(formatMessage(...), GetGameTimer()))
end

CBKAI.Log = M

if type(package) == 'table' then
    package.loaded = package.loaded or {}
    package.preload = package.preload or {}

    package.loaded['log'] = M
    package.loaded['shared.log'] = M

    package.preload['log'] = function()
        return M
    end

    package.preload['shared.log'] = function()
        return M
    end
end

return M
