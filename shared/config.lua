Config = Config or {}

local function deepCopy(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function deepMerge(defaults, target)
    for k, v in pairs(defaults) do
        if type(v) == 'table' then
            if type(target[k]) ~= 'table' then
                target[k] = deepCopy(v)
            else
                deepMerge(v, target[k])
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

CBKAI_LoadLegacyConfig = function()
    local resourceName = GetCurrentResourceName()
    local raw = LoadResourceFile(resourceName, 'config.lua')

    if not raw or raw == '' then
        return false, 'config.lua not found or empty'
    end

    local chunk, err = load(raw, '@config.lua')
    if not chunk then
        return false, err
    end

    local ok, runErr = pcall(chunk)
    if not ok then
        return false, runErr
    end

    return true
end

local defaults = {
    Security = {
        rateLimitWindowMs = 5000,
        requestInitMaxCalls = 12,
        runtimeReportMaxCalls = 24,
        maxPayloadNodes = 2500,
        maxPayloadDepth = 12,
        commandCooldownMs = 1000,
        telemetryIntervalMs = 300000,
    },
    Commands = {
        statusCommand = 'npcstatus',
    }
}

deepMerge(defaults, Config)

CBKAI_Defaults = defaults
CBKAI_DeepCopy = deepCopy
CBKAI_DeepMerge = deepMerge
