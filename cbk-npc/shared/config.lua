Config = Config or {}


CBKAI = CBKAI or {}

local Utils = CBKAI.Utils or require 'utils'
local deepCopy = Utils.deepCopy
local deepMerge = Utils.deepMerge or Utils.deepCopy

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

Config = deepMerge(defaults, Config)

CBKAI_Defaults = defaults
CBKAI_DeepCopy = deepCopy
CBKAI_DeepMerge = deepMerge
