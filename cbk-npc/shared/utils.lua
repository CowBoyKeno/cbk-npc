-- cbk-npc/shared/utils.lua
-- Shared utility functions for cbk-npc (deduplicated helpers)

CBKAI = CBKAI or {}

local M = {}

function M.clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function M.deepCopy(value)
    if type(value) ~= 'table' then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = M.deepCopy(v)
    end
    return copy
end

function M.deepClone(value)
    -- Alias for deepCopy for legacy code
    return M.deepCopy(value)
end

function M.deepMerge(base, overrides)
    if type(base) ~= 'table' then
        return M.deepCopy(overrides)
    end

    local merged = M.deepCopy(base)
    if type(overrides) ~= 'table' then
        return merged
    end

    for key, value in pairs(overrides) do
        if type(value) == 'table' and type(merged[key]) == 'table' then
            merged[key] = M.deepMerge(merged[key], value)
        else
            merged[key] = M.deepCopy(value)
        end
    end

    return merged
end

CBKAI.Utils = M

if type(package) == 'table' then
    package.loaded = package.loaded or {}
    package.preload = package.preload or {}

    package.loaded['utils'] = M
    package.loaded['shared.utils'] = M

    package.preload['utils'] = function()
        return M
    end

    package.preload['shared.utils'] = function()
        return M
    end
end

return M
