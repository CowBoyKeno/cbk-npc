
-- NUI path whitelist for cbk:setValue
local NUI_PATH_WHITELIST = {
    ["EnableNPCs"] = true,
    ["PopulationDensity"] = true,
    ["SpawnControl"] = true,
    ["NPCBehavior"] = true,
    ["VehicleSettings"] = true,
    ["ScenarioSettings"] = true,
    ["TimeBasedSettings"] = true,
    ["WantedSystem"] = true,
    ["Advanced"] = true,
    ["Events"] = true,
    ["Blacklist"] = true,
    ["Whitelist"] = true,
    ["Relationships"] = true,
}

local function isNuiPathAllowed(path)
    if type(path) ~= "table" or #path == 0 or #path > 3 then -- limit depth
        return false
    end
    if not NUI_PATH_WHITELIST[path[1]] then
        return false
    end
    return true
end
CBKAI = CBKAI or {}

local function safeRequire(moduleName)
    if type(moduleName) ~= 'string' or moduleName == '' then
        return nil
    end

    local requireFn = require
    if type(requireFn) ~= 'function' then
        return nil
    end

    local ok, result = pcall(requireFn, moduleName)
    if ok and type(result) == 'table' then
        return result
    end

    return nil
end

local function resolveUtils()
    if type(CBKAI.Utils) == 'table' then
        return CBKAI.Utils
    end
    local loaded = safeRequire('utils') or safeRequire('shared.utils')
    if type(loaded) == 'table' then
        CBKAI.Utils = loaded
        return loaded
    end
    error('cbk-npc: utils module unavailable')
end

local Utils = resolveUtils()
local deepCopy = Utils.deepCopy

local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= 'table' then
        return a == b
    end

    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then
            return false
        end
    end

    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end

local function buildPatch(path, oldValue, newValue, ops)
    if type(oldValue) ~= type(newValue) then
        ops[#ops + 1] = { path = path, value = deepCopy(newValue) }
        return
    end

    if type(newValue) ~= 'table' then
        if oldValue ~= newValue then
            ops[#ops + 1] = { path = path, value = newValue }
        end
        return
    end

    local keys = {}
    for k, _ in pairs(oldValue) do keys[k] = true end
    for k, _ in pairs(newValue) do keys[k] = true end

    for key, _ in pairs(keys) do
        local childPath = deepCopy(path)
        childPath[#childPath + 1] = key
        if oldValue[key] == nil then
            ops[#ops + 1] = { path = childPath, value = deepCopy(newValue[key]) }
        elseif newValue[key] == nil then
            ops[#ops + 1] = { path = childPath, value = nil, remove = true }
        else
            buildPatch(childPath, oldValue[key], newValue[key], ops)
        end
    end
end

local function sanitizeConfig(config)
    local schema = deepCopy(Config)

    local function apply(candidate, template)
        if type(template) ~= 'table' then
            if type(candidate) == type(template) then
                return candidate
            end
            return template
        end

        if type(candidate) ~= 'table' then
            return deepCopy(template)
        end

        local out = {}
        for key, value in pairs(template) do
            out[key] = apply(candidate[key], value)
        end
        return out
    end

    return apply(config, schema)
end

local syncState = {
    config = deepCopy(Config),
    revision = 1,
}

local panelLock = {
    owner = 0,
    ownerName = nil,
    acquiredAt = 0,
}

local PANEL_PROFILE_FILE = 'profiles/cbk_panel_runtime.json'
local PANEL_PROFILE_DIR = 'profiles/cbk_panel/'
local PANEL_PROFILE_INDEX_FILE = 'profiles/cbk_panel/index.json'

local function stringifyAuditValue(value)
    if type(value) == 'table' then
        if type(json) == 'table' and type(json.encode) == 'function' then
            local ok, encoded = pcall(json.encode, value)
            if ok and type(encoded) == 'string' then
                return encoded
            end
        end
        return '<table>'
    end

    return tostring(value)
end

local function auditPanelEvent(source, action, details)
    local ok, playerName = pcall(GetPlayerName, source)
    local name = (ok and playerName) and playerName or ('id:%d'):format(source)
    local timestamp = os.date('%m-%d-%Y %H:%M:%S')
    print(('[CBK PANEL][%s] src=%d name=%s action=%s %s'):format(timestamp, source, name, action, details or ''))
end

local function sanitizeProfileName(name)
    if type(name) ~= 'string' then
        return nil
    end

    local cleaned = string.lower(name)
    cleaned = cleaned:gsub('^%s+', ''):gsub('%s+$', '')
    cleaned = cleaned:gsub('[^%w_%-%s]', '')
    cleaned = cleaned:gsub('%s+', '_')

    if cleaned == '' then
        return nil
    end

    if #cleaned > 40 then
        cleaned = cleaned:sub(1, 40)
    end

    if not cleaned:match('^[%w_%-]+$') then
        return nil
    end

    return cleaned
end

local function profileFilePath(name)
    return PANEL_PROFILE_DIR .. name .. '.json'
end

local function loadProfileIndex()
    if type(json) ~= 'table' or type(json.decode) ~= 'function' then
        return { names = {}, meta = {} }
    end

    local raw = LoadResourceFile(GetCurrentResourceName(), PANEL_PROFILE_INDEX_FILE)
    if type(raw) ~= 'string' or raw == '' then
        return { names = {}, meta = {} }
    end

    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= 'table' or type(parsed.names) ~= 'table' then
        return { names = {}, meta = {} }
    end

    local names = {}
    for i = 1, #parsed.names do
        local profileName = sanitizeProfileName(parsed.names[i])
        if profileName then
            names[#names + 1] = profileName
        end
    end
    table.sort(names)

    local meta = {}
    if type(parsed.meta) == 'table' then
        for k, v in pairs(parsed.meta) do
            local safeKey = sanitizeProfileName(k)
            if safeKey and type(v) == 'table' then
                meta[safeKey] = {
                    savedAt    = type(v.savedAt)    == 'number' and v.savedAt    or nil,
                    savedBy    = type(v.savedBy)    == 'string' and v.savedBy    or nil,
                    lastUsedAt = type(v.lastUsedAt) == 'number' and v.lastUsedAt or nil,
                    lastUsedBy = type(v.lastUsedBy) == 'string' and v.lastUsedBy or nil,
                }
            end
        end
    end

    return { names = names, meta = meta }
end

local function saveProfileIndex(names, meta)
    if type(json) ~= 'table' or type(json.encode) ~= 'function' then
        return false, 'json_runtime_unavailable'
    end

    table.sort(names)
    local encoded = json.encode({ names = names, meta = meta or {} })
    if type(encoded) ~= 'string' or encoded == '' then
        return false, 'encode_failed'
    end

    local ok = SaveResourceFile(GetCurrentResourceName(), PANEL_PROFILE_INDEX_FILE, encoded, #encoded)
    if not ok then
        return false, 'index_write_failed'
    end

    return true
end

local function listPanelProfiles()
    local index = loadProfileIndex()
    local names = index.names
    local meta  = index.meta

    local hasRuntime = false
    for i = 1, #names do
        if names[i] == 'runtime' then
            hasRuntime = true
            break
        end
    end

    if not hasRuntime then
        names[#names + 1] = 'runtime'
        table.sort(names)
    end

    local out = {}
    for i = 1, #names do
        local n = names[i]
        local m = meta[n] or {}
        out[#out + 1] = {
            name       = n,
            savedAt    = m.savedAt,
            savedBy    = m.savedBy,
            lastUsedAt = m.lastUsedAt,
            lastUsedBy = m.lastUsedBy,
        }
    end

    return out
end

local function saveNamedPanelProfile(name, config, savedBy)
    local safeName = sanitizeProfileName(name)
    if not safeName then
        return false, 'invalid_profile_name'
    end

    if type(json) ~= 'table' or type(json.encode) ~= 'function' then
        return false, 'json_runtime_unavailable'
    end

    local savedAt = os.time()
    local encoded = json.encode({
        schema  = 'cbk-panel-profile-v1',
        name    = safeName,
        savedAt = savedAt,
        savedBy = type(savedBy) == 'string' and savedBy or nil,
        config  = config,
    })

    if type(encoded) ~= 'string' or encoded == '' then
        return false, 'encode_failed'
    end

    local ok = SaveResourceFile(GetCurrentResourceName(), profileFilePath(safeName), encoded, #encoded)
    if not ok then
        return false, 'write_failed'
    end

    local index = loadProfileIndex()
    local names = index.names
    local meta  = index.meta

    local exists = false
    for i = 1, #names do
        if names[i] == safeName then
            exists = true
            break
        end
    end

    if not exists then
        names[#names + 1] = safeName
    end

    local existing = meta[safeName] or {}
    meta[safeName] = {
        savedAt    = savedAt,
        savedBy    = type(savedBy) == 'string' and savedBy or existing.savedBy,
        lastUsedAt = existing.lastUsedAt,
        lastUsedBy = existing.lastUsedBy,
    }

    local savedIndex, indexErr = saveProfileIndex(names, meta)
    if not savedIndex then
        return false, indexErr or 'index_write_failed'
    end

    return true, safeName
end

local function loadNamedPanelProfile(name, lastUsedBy)
    local safeName = sanitizeProfileName(name)
    if not safeName then
        return false, 'invalid_profile_name'
    end

    if type(json) ~= 'table' or type(json.decode) ~= 'function' then
        return false, 'json_runtime_unavailable'
    end

    local raw = LoadResourceFile(GetCurrentResourceName(), profileFilePath(safeName))
    if type(raw) ~= 'string' or raw == '' then
        if safeName == 'runtime' then
            return true, deepCopy(syncState.config), safeName
        end
        return false, 'profile_not_found'
    end

    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= 'table' or type(parsed.config) ~= 'table' then
        return false, 'profile_invalid'
    end

    if type(lastUsedBy) == 'string' and lastUsedBy ~= '' then
        local index = loadProfileIndex()
        local m = index.meta[safeName] or {}
        m.lastUsedAt = os.time()
        m.lastUsedBy = lastUsedBy
        index.meta[safeName] = m
        saveProfileIndex(index.names, index.meta)
    end

    return true, parsed.config, safeName
end

local function deleteNamedPanelProfile(name)
    local safeName = sanitizeProfileName(name)
    if not safeName then
        return false, 'invalid_profile_name'
    end

    if safeName == 'runtime' then
        return false, 'runtime_profile_protected'
    end

    local ok = SaveResourceFile(GetCurrentResourceName(), profileFilePath(safeName), '', 0)
    if not ok then
        return false, 'delete_failed'
    end

    local index = loadProfileIndex()
    local out = {}
    for i = 1, #index.names do
        if index.names[i] ~= safeName then
            out[#out + 1] = index.names[i]
        end
    end
    index.meta[safeName] = nil

    local savedIndex, indexErr = saveProfileIndex(out, index.meta)
    if not savedIndex then
        return false, indexErr or 'index_write_failed'
    end

    return true, safeName
end

local function getPlayerNameSafe(source)
    local ok, name = pcall(GetPlayerName, source)
    if not ok then
        return nil
    end
    return name
end

local function getLockOwnerLabel()
    if panelLock.owner == 0 then
        return 'none'
    end

    if panelLock.ownerName and panelLock.ownerName ~= '' then
        return ('%s (%d)'):format(panelLock.ownerName, panelLock.owner)
    end

    return ('id:%d'):format(panelLock.owner)
end

local function canUsePanelLock(source)
    if panelLock.owner == 0 or panelLock.owner == source then
        return true
    end

    return false
end

local function acquirePanelLock(source)
    panelLock.owner = source
    panelLock.ownerName = getPlayerNameSafe(source) or ('id:%d'):format(source)
    panelLock.acquiredAt = GetGameTimer()
end

local function releasePanelLock(source)
    if panelLock.owner ~= source then
        return false
    end

    panelLock.owner = 0
    panelLock.ownerName = nil
    panelLock.acquiredAt = 0
    return true
end

local function savePanelProfile(config, savedBy)
    if type(json) ~= 'table' or type(json.encode) ~= 'function' then
        return false, 'json_runtime_unavailable'
    end

    local encoded = json.encode({
        schema  = 'cbk-panel-profile-v1',
        savedAt = os.time(),
        config  = config,
    })

    if type(encoded) ~= 'string' or encoded == '' then
        return false, 'encode_failed'
    end

    local ok = SaveResourceFile(GetCurrentResourceName(), PANEL_PROFILE_FILE, encoded, #encoded)
    if not ok then
        return false, 'write_failed'
    end

    local namedSaved, namedErr = saveNamedPanelProfile('runtime', config, savedBy)
    if not namedSaved then
        return false, namedErr or 'named_profile_write_failed'
    end

    return true
end

local function loadPanelProfile(lastUsedBy)
    if type(json) ~= 'table' or type(json.decode) ~= 'function' then
        return false, 'json_runtime_unavailable'
    end

    local raw = LoadResourceFile(GetCurrentResourceName(), PANEL_PROFILE_FILE)
    if type(raw) ~= 'string' or raw == '' then
        local ok, config, safeName = loadNamedPanelProfile('runtime', lastUsedBy)
        if ok then
            return true, config, safeName
        end
        return true, deepCopy(syncState.config), 'runtime'
    end

    local ok, parsed = pcall(json.decode, raw)
    if not ok or type(parsed) ~= 'table' or type(parsed.config) ~= 'table' then
        local loaded, config, safeName = loadNamedPanelProfile('runtime', lastUsedBy)
        if loaded then
            return true, config, safeName
        end
        return true, deepCopy(syncState.config), 'runtime'
    end

    if type(lastUsedBy) == 'string' and lastUsedBy ~= '' then
        local index = loadProfileIndex()
        local m = index.meta['runtime'] or {}
        m.lastUsedAt = os.time()
        m.lastUsedBy = lastUsedBy
        index.meta['runtime'] = m
        saveProfileIndex(index.names, index.meta)
    end

    return true, parsed.config
end

local function hasPersistedRuntimeProfile()
    local rawRuntime = LoadResourceFile(GetCurrentResourceName(), PANEL_PROFILE_FILE)
    if type(rawRuntime) == 'string' and rawRuntime ~= '' then
        return true
    end

    local rawNamedRuntime = LoadResourceFile(GetCurrentResourceName(), profileFilePath('runtime'))
    return type(rawNamedRuntime) == 'string' and rawNamedRuntime ~= ''
end

local function sendPanelProfileList(target)
    TriggerClientEvent('cbk_ai:cl:panelProfileList', target, {
        profiles = listPanelProfiles(),
    })
end

local function sendFullConfig(target)
    TriggerClientEvent('cbk_ai:cl:syncFull', target, {
        revision = syncState.revision,
        config = syncState.config,
    })
end

local function broadcastPatch(previous, nextConfig)
    local ops = {}
    buildPatch({}, previous, nextConfig, ops)
    if #ops == 0 then
        return
    end

    syncState.revision = syncState.revision + 1
    TriggerClientEvent('cbk_ai:cl:syncPatch', -1, {
        revision = syncState.revision,
        ops = ops,
    })
end

local function applyServerConfig(nextConfig)
    local prev = syncState.config
    syncState.config = nextConfig
    Config = nextConfig
    broadcastPatch(prev, nextConfig)
end

local function normalizeConfig(config)
    config = sanitizeConfig(config)

    local function clamp(v, minV, maxV)
        if v < minV then return minV end
        if v > maxV then return maxV end
        return v
    end

    local function clampInt(v, minV, maxV)
        return math.floor(clamp(v, minV, maxV))
    end

    local function normalizeEnum(value, allowed, fallback)
        for i = 1, #allowed do
            if value == allowed[i] then
                return value
            end
        end

        return fallback
    end

    config.PopulationDensity.pedDensity = clamp(config.PopulationDensity.pedDensity, 0.0, 1.0)
    config.PopulationDensity.vehicleDensity = clamp(config.PopulationDensity.vehicleDensity, 0.0, 1.0)
    config.PopulationDensity.parkedVehicleDensity = clamp(config.PopulationDensity.parkedVehicleDensity, 0.0, 1.0)
    config.PopulationDensity.scenarioPedDensity = clamp(config.PopulationDensity.scenarioPedDensity, 0.0, 1.0)

    config.TimeBasedSettings.daySettings.pedDensity = clamp(config.TimeBasedSettings.daySettings.pedDensity, 0.0, 1.0)
    config.TimeBasedSettings.daySettings.vehicleDensity = clamp(config.TimeBasedSettings.daySettings.vehicleDensity, 0.0, 1.0)
    config.TimeBasedSettings.nightSettings.pedDensity = clamp(config.TimeBasedSettings.nightSettings.pedDensity, 0.0, 1.0)
    config.TimeBasedSettings.nightSettings.vehicleDensity = clamp(config.TimeBasedSettings.nightSettings.vehicleDensity, 0.0, 1.0)

    config.NPCBehavior.npcAccuracy = clamp(config.NPCBehavior.npcAccuracy, 0.0, 1.0)
    config.NPCBehavior.npcShootRate = clampInt(config.NPCBehavior.npcShootRate, 1, 1000)
    config.NPCBehavior.combatAbility = clampInt(config.NPCBehavior.combatAbility, 0, 2)
    config.NPCBehavior.combatMovement = clampInt(config.NPCBehavior.combatMovement, 0, 3)
    config.NPCBehavior.pedAlertness = clampInt(config.NPCBehavior.pedAlertness, 0, 3)
    config.NPCBehavior.pedSeeingRange = clamp(config.NPCBehavior.pedSeeingRange, 0.0, 1000.0)
    config.NPCBehavior.pedHearingRange = clamp(config.NPCBehavior.pedHearingRange, 0.0, 1000.0)
    config.NPCBehavior.moveRateOverride = clamp(config.NPCBehavior.moveRateOverride, 0.0, 1.15)
    config.NPCBehavior.npcDrivingStyle = normalizeEnum(
        config.NPCBehavior.npcDrivingStyle,
        { 'normal', 'careful', 'reckless', 'ignored' },
        'careful'
    )

    config.VehicleSettings.maxVehicles = clampInt(config.VehicleSettings.maxVehicles, 0, 2048)
    config.VehicleSettings.playerVehicleProtectionMs = clampInt(config.VehicleSettings.playerVehicleProtectionMs, 0, 86400000)
    config.VehicleSettings.playerVehicleProtectionDistance = clamp(config.VehicleSettings.playerVehicleProtectionDistance, 0.0, 5000.0)

    local emergency = config.VehicleSettings.emergencyVehicleBehavior
    emergency.slowPassRadius = clamp(emergency.slowPassRadius, 0.0, 300.0)
    emergency.slowPassSpeed = clamp(emergency.slowPassSpeed, 0.0, 80.0)
    emergency.safeBypassLookAhead = clamp(emergency.safeBypassLookAhead, 2.0, 80.0)
    emergency.safeBypassLateralOffset = clamp(emergency.safeBypassLateralOffset, 1.0, 20.0)
    emergency.safeBypassClearanceRadius = clamp(emergency.safeBypassClearanceRadius, 1.0, 30.0)
    emergency.safeBypassSpeedMph = clamp(emergency.safeBypassSpeedMph, 0.0, 80.0)
    emergency.safeBypassTaskMs = clampInt(emergency.safeBypassTaskMs, 0, 30000)
    emergency.safeBypassDrivingStyle = clampInt(emergency.safeBypassDrivingStyle, 0, 2147483647)
    emergency.safeBypassForceDrivingStyle = clampInt(emergency.safeBypassForceDrivingStyle, 0, 2147483647)
    emergency.maxStoppedEmergencyAnchors = clampInt(emergency.maxStoppedEmergencyAnchors, 0, 32)
    emergency.stoppedEmergencyBubbleSearchRadius = clamp(emergency.stoppedEmergencyBubbleSearchRadius, 0.0, 500.0)
    emergency.stoppedEmergencyBubbleRadius = clamp(emergency.stoppedEmergencyBubbleRadius, 0.0, 150.0)
    emergency.stoppedEmergencyMaxSpeedMph = clamp(emergency.stoppedEmergencyMaxSpeedMph, 0.0, 40.0)
    emergency.stoppedEmergencyHardStopRadius = clamp(emergency.stoppedEmergencyHardStopRadius, 0.0, 75.0)
    emergency.stoppedEmergencyHardStopActionMs = clampInt(emergency.stoppedEmergencyHardStopActionMs, 0, 15000)
    emergency.bypassMinAlignmentDot = clamp(emergency.bypassMinAlignmentDot, 0.0, 1.0)
    emergency.sameDirectionDotMin = clamp(emergency.sameDirectionDotMin, -1.0, 1.0)
    emergency.minBehindDistanceForResponse = clamp(emergency.minBehindDistanceForResponse, 0.0, 200.0)
    emergency.courtesyRadius = clamp(emergency.courtesyRadius, 0.0, 500.0)

    config.WantedSystem.maxWantedLevel = clampInt(config.WantedSystem.maxWantedLevel, 0, 5)

    config.Relationships.playerToNPC = clampInt(config.Relationships.playerToNPC, 0, 5)
    config.Relationships.npcToPlayer = clampInt(config.Relationships.npcToPlayer, 0, 5)
    config.Relationships.npcToNPC = clampInt(config.Relationships.npcToNPC, 0, 5)
    config.Relationships.copsToPlayer = clampInt(config.Relationships.copsToPlayer, 0, 5)
    config.Relationships.gangsToPlayer = clampInt(config.Relationships.gangsToPlayer, 0, 5)
    config.Relationships.copsToGangs = clampInt(config.Relationships.copsToGangs, 0, 5)

    config.Advanced.updateInterval = clampInt(config.Advanced.updateInterval, 250, 60000)
    config.Advanced.cleanupInterval = clampInt(config.Advanced.cleanupInterval, 1000, 300000)
    config.Advanced.cleanupDistance = clamp(config.Advanced.cleanupDistance, 100.0, 5000.0)
    config.Advanced.maxNPCDistance = clamp(config.Advanced.maxNPCDistance, 50.0, 2500.0)
    config.Advanced.maxAmbientPeds = clampInt(config.Advanced.maxAmbientPeds, 0, 512)
    config.Advanced.cleanupDeadNPCsAfterMs = clampInt(config.Advanced.cleanupDeadNPCsAfterMs, 0, 3600000)
    config.Advanced.cleanupWreckedVehiclesAfterMs = clampInt(config.Advanced.cleanupWreckedVehiclesAfterMs, 0, 3600000)
    config.Advanced.cleanupAbandonedVehiclesAfterMs = clampInt(config.Advanced.cleanupAbandonedVehiclesAfterMs, 0, 3600000)
    config.Advanced.abandonedVehicleSpeedThresholdMph = clamp(config.Advanced.abandonedVehicleSpeedThresholdMph, 0.0, 20.0)
    config.Advanced.suppressionLevel = normalizeEnum(
        config.Advanced.suppressionLevel,
        { 'none', 'low', 'medium', 'high', 'maximum' },
        'medium'
    )

    config.Security.rateLimitWindowMs = clampInt(config.Security.rateLimitWindowMs, 250, 600000)
    config.Security.requestInitMaxCalls = clampInt(config.Security.requestInitMaxCalls, 1, 120)
    config.Security.runtimeReportMaxCalls = clampInt(config.Security.runtimeReportMaxCalls, 1, 240)
    config.Security.maxPayloadNodes = clampInt(config.Security.maxPayloadNodes, 64, 20000)
    config.Security.maxPayloadDepth = clampInt(config.Security.maxPayloadDepth, 2, 32)
    config.Security.commandCooldownMs = clampInt(config.Security.commandCooldownMs, 100, 60000)
    config.Security.telemetryIntervalMs = clampInt(config.Security.telemetryIntervalMs, 10000, 3600000)

    return config
end

local PANEL_EDITABLE_PATHS = {
    ['EnableNPCs'] = { type = 'boolean' },
    ['PopulationDensity.enabled'] = { type = 'boolean' },
    ['PopulationDensity.pedDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['PopulationDensity.vehicleDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['PopulationDensity.parkedVehicleDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['PopulationDensity.scenarioPedDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['SpawnControl.enabled'] = { type = 'boolean' },
    ['SpawnControl.disableAmbientPeds'] = { type = 'boolean' },
    ['SpawnControl.disableVehicleSpawn'] = { type = 'boolean' },
    ['SpawnControl.disableParkedVehicles'] = { type = 'boolean' },
    ['SpawnControl.disableScenarioPeds'] = { type = 'boolean' },
    ['VehicleSettings.enableTraffic'] = { type = 'boolean' },
    ['VehicleSettings.maxVehicles'] = { type = 'number', min = 0, max = 2048, integer = true },
    ['ScenarioSettings.disableAllScenarios'] = { type = 'boolean' },
    ['ScenarioSettings.disableAnimals'] = { type = 'boolean' },
    ['TimeBasedSettings.enabled'] = { type = 'boolean' },
    ['TimeBasedSettings.daySettings.enableScenarios'] = { type = 'boolean' },
    ['TimeBasedSettings.daySettings.pedDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['TimeBasedSettings.daySettings.vehicleDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['TimeBasedSettings.nightSettings.enableScenarios'] = { type = 'boolean' },
    ['TimeBasedSettings.nightSettings.pedDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['TimeBasedSettings.nightSettings.vehicleDensity'] = { type = 'number', min = 0.0, max = 1.0 },
    ['WantedSystem.disableWantedLevel'] = { type = 'boolean' },
    ['WantedSystem.disablePoliceResponse'] = { type = 'boolean' },
    ['WantedSystem.maxWantedLevel'] = { type = 'number', min = 0, max = 5, integer = true },
    ['Advanced.updateInterval'] = { type = 'number', min = 250, max = 60000, integer = true },
    ['Advanced.maxNPCDistance'] = { type = 'number', min = 50.0, max = 2500.0 },
    ['Advanced.maxAmbientPeds'] = { type = 'number', min = 0, max = 512, integer = true },
    ['Advanced.cleanupInterval'] = { type = 'number', min = 1000, max = 300000, integer = true },
    ['Advanced.suppressionLevel'] = {
        type = 'enum',
        values = { none = true, low = true, medium = true, high = true, maximum = true }
    },
    ['NPCBehavior.disableNPCCombat'] = { type = 'boolean' },
    ['NPCBehavior.npcAccuracy'] = { type = 'number', min = 0.0, max = 1.0 },
    ['NPCBehavior.pedSeeingRange'] = { type = 'number', min = 0.0, max = 1000.0 },
    ['NPCBehavior.pedHearingRange'] = { type = 'number', min = 0.0, max = 1000.0 },
    ['NPCBehavior.ignorePlayer'] = { type = 'boolean' },
    ['NPCBehavior.fleeFromPlayer'] = { type = 'boolean' },
    ['NPCBehavior.npcDrivingStyle'] = {
        type = 'enum',
        values = { normal = true, careful = true, reckless = true, ignored = true }
    },
    ['VehicleSettings.emergencyVehicleBehavior.enabled'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.requireSiren'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.slowPassRadius'] = { type = 'number', min = 0.0, max = 300.0 },
    ['VehicleSettings.emergencyVehicleBehavior.slowPassSpeed'] = { type = 'number', min = 0.0, max = 80.0 },
    ['VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyBubbleRadius'] = { type = 'number', min = 0.0, max = 150.0 },
    ['VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyMaxSpeedMph'] = { type = 'number', min = 0.0, max = 40.0 },
    ['VehicleSettings.emergencyVehicleBehavior.courtesyRadius'] = { type = 'number', min = 0.0, max = 500.0 },
    ['ScenarioSettings.disableCops'] = { type = 'boolean' },
    ['ScenarioSettings.disableParamedics'] = { type = 'boolean' },
    ['WantedSystem.disablePoliceScanner'] = { type = 'boolean' },
    ['WantedSystem.disablePoliceHelicopters'] = { type = 'boolean' },
    ['Relationships.enabled'] = { type = 'boolean' },
    ['Relationships.playerToNPC'] = { type = 'number', min = 0, max = 5, integer = true },
    ['Relationships.npcToPlayer'] = { type = 'number', min = 0, max = 5, integer = true },
    ['Relationships.copsToPlayer'] = { type = 'number', min = 0, max = 5, integer = true },
    ['Relationships.gangsToPlayer'] = { type = 'number', min = 0, max = 5, integer = true },
    ['Advanced.cleanupDistance'] = { type = 'number', min = 100.0, max = 5000.0 },
}

local function extendPanelEditablePaths(entries)
    for path, rule in pairs(entries) do
        PANEL_EDITABLE_PATHS[path] = rule
    end
end

extendPanelEditablePaths({
    ['NPCBehavior.panicFromGunfire'] = { type = 'boolean' },
    ['NPCBehavior.reactToExplosions'] = { type = 'boolean' },
    ['NPCBehavior.reactToFire'] = { type = 'boolean' },
    ['NPCBehavior.reactToDeadBodies'] = { type = 'boolean' },
    ['NPCBehavior.reactToSirens'] = { type = 'boolean' },
    ['NPCBehavior.disableNPCWeapons'] = { type = 'boolean' },
    ['NPCBehavior.npcShootRate'] = { type = 'number', min = 1, max = 1000, integer = true },
    ['NPCBehavior.combatAbility'] = { type = 'number', min = 0, max = 2, integer = true },
    ['NPCBehavior.combatMovement'] = { type = 'number', min = 0, max = 3, integer = true },
    ['NPCBehavior.pedAlertness'] = { type = 'number', min = 0, max = 3, integer = true },
    ['NPCBehavior.moveRateOverride'] = { type = 'number', min = 0.0, max = 1.15 },
    ['NPCBehavior.disableNPCDriving'] = { type = 'boolean' },
    ['NPCBehavior.respectTrafficLights'] = { type = 'boolean' },
    ['NPCBehavior.avoidTraffic'] = { type = 'boolean' },
    ['NPCBehavior.disableAmbientSpeech'] = { type = 'boolean' },
    ['NPCBehavior.disableAmbientHorns'] = { type = 'boolean' },
    ['NPCBehavior.disablePainAudio'] = { type = 'boolean' },
    ['NPCBehavior.disableAmbientAnims'] = { type = 'boolean' },
    ['NPCBehavior.disableAmbientBaseAnims'] = { type = 'boolean' },
    ['NPCBehavior.disableGestureAnims'] = { type = 'boolean' },
    ['NPCBehavior.allowPlayerMelee'] = { type = 'boolean' },
    ['NPCBehavior.npcCanRagdoll'] = { type = 'boolean' },
    ['NPCBehavior.npcCanBeKnockedOffBike'] = { type = 'boolean' },
    ['NPCBehavior.canEvasiveDive'] = { type = 'boolean' },
    ['NPCBehavior.canCowerInCover'] = { type = 'boolean' },
    ['NPCBehavior.canBeTargetted'] = { type = 'boolean' },
    ['NPCBehavior.canBeTargettedByPlayer'] = { type = 'boolean' },
    ['NPCBehavior.canBeShotInVehicle'] = { type = 'boolean' },
    ['NPCBehavior.canBeDraggedOutOfVehicle'] = { type = 'boolean' },
    ['NPCBehavior.canUseLadders'] = { type = 'boolean' },
    ['NPCBehavior.canUseClimbovers'] = { type = 'boolean' },
    ['NPCBehavior.canDropFromHeight'] = { type = 'boolean' },
    ['NPCBehavior.pathAvoidFire'] = { type = 'boolean' },

    ['VehicleSettings.disablePoliceVehicles'] = { type = 'boolean' },
    ['VehicleSettings.disableAmbulanceVehicles'] = { type = 'boolean' },
    ['VehicleSettings.disableFiretruckVehicles'] = { type = 'boolean' },
    ['VehicleSettings.disableBoats'] = { type = 'boolean' },
    ['VehicleSettings.disablePlanes'] = { type = 'boolean' },
    ['VehicleSettings.disableHelicopters'] = { type = 'boolean' },
    ['VehicleSettings.disableTrains'] = { type = 'boolean' },
    ['VehicleSettings.vehiclesRespectLights'] = { type = 'boolean' },
    ['VehicleSettings.vehiclesUseIndicators'] = { type = 'boolean' },
    ['VehicleSettings.enableVehicleDamage'] = { type = 'boolean' },
    ['VehicleSettings.vehiclesAvoidPlayer'] = { type = 'boolean' },
    ['VehicleSettings.preservePlayerLastVehicle'] = { type = 'boolean' },
    ['VehicleSettings.playerVehicleProtectionMs'] = { type = 'number', min = 0, max = 86400000, integer = true },
    ['VehicleSettings.playerVehicleProtectionDistance'] = { type = 'number', min = 0.0, max = 5000.0 },

    ['VehicleSettings.emergencyVehicleBehavior.slowPassEnabled'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.safeOncomingBypassEnabled'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassLookAhead'] = { type = 'number', min = 2.0, max = 80.0 },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassLateralOffset'] = { type = 'number', min = 1.0, max = 20.0 },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassClearanceRadius'] = { type = 'number', min = 1.0, max = 30.0 },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassSpeedMph'] = { type = 'number', min = 0.0, max = 80.0 },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassTaskMs'] = { type = 'number', min = 0, max = 30000, integer = true },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassDrivingStyle'] = { type = 'number', min = 0, max = 2147483647, integer = true },
    ['VehicleSettings.emergencyVehicleBehavior.safeBypassForceDrivingStyle'] = { type = 'number', min = 0, max = 2147483647, integer = true },
    ['VehicleSettings.emergencyVehicleBehavior.bypassMinAlignmentDot'] = { type = 'number', min = 0.0, max = 1.0 },
    ['VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyBubbleEnabled'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.maxStoppedEmergencyAnchors'] = { type = 'number', min = 0, max = 32, integer = true },
    ['VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyBubbleSearchRadius'] = { type = 'number', min = 0.0, max = 500.0 },
    ['VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyHardStopRadius'] = { type = 'number', min = 0.0, max = 75.0 },
    ['VehicleSettings.emergencyVehicleBehavior.stoppedEmergencyHardStopActionMs'] = { type = 'number', min = 0, max = 15000, integer = true },
    ['VehicleSettings.emergencyVehicleBehavior.sameDirectionDotMin'] = { type = 'number', min = -1.0, max = 1.0 },
    ['VehicleSettings.emergencyVehicleBehavior.minBehindDistanceForResponse'] = { type = 'number', min = 0.0, max = 200.0 },
    ['VehicleSettings.emergencyVehicleBehavior.disableHornNearEmergency'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.disableSpeechNearEmergency'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.detectPolice'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.detectAmbulance'] = { type = 'boolean' },
    ['VehicleSettings.emergencyVehicleBehavior.detectFiretruck'] = { type = 'boolean' },

    ['ScenarioSettings.disableFiremen'] = { type = 'boolean' },
    ['ScenarioSettings.disableVendors'] = { type = 'boolean' },
    ['ScenarioSettings.disableBeggars'] = { type = 'boolean' },
    ['ScenarioSettings.disableBuskers'] = { type = 'boolean' },
    ['ScenarioSettings.disableHookers'] = { type = 'boolean' },
    ['ScenarioSettings.disableDealer'] = { type = 'boolean' },
    ['ScenarioSettings.disableCrimeScenarios'] = { type = 'boolean' },
    ['ScenarioSettings.disableBirds'] = { type = 'boolean' },
    ['ScenarioSettings.disableFish'] = { type = 'boolean' },
    ['ScenarioSettings.disableSeagulls'] = { type = 'boolean' },

    ['WantedSystem.disablePoliceChase'] = { type = 'boolean' },
    ['WantedSystem.npcReportCrimes'] = { type = 'boolean' },
    ['WantedSystem.npcReportVehicleTheft'] = { type = 'boolean' },
    ['WantedSystem.npcReportAssault'] = { type = 'boolean' },
    ['WantedSystem.npcReportShooting'] = { type = 'boolean' },

    ['Relationships.npcToNPC'] = { type = 'number', min = 0, max = 5, integer = true },
    ['Relationships.copsToGangs'] = { type = 'number', min = 0, max = 5, integer = true },

    ['Advanced.standaloneAmbientControl'] = { type = 'boolean' },
    ['Advanced.autoCleanupEnabled'] = { type = 'boolean' },
    ['Advanced.deleteDeadNPCs'] = { type = 'boolean' },
    ['Advanced.cleanupDeadNPCsAfterMs'] = { type = 'number', min = 0, max = 3600000, integer = true },
    ['Advanced.deleteWreckedEmptyVehicles'] = { type = 'boolean' },
    ['Advanced.cleanupWreckedVehiclesAfterMs'] = { type = 'number', min = 0, max = 3600000, integer = true },
    ['Advanced.deleteAbandonedEmptyVehicles'] = { type = 'boolean' },
    ['Advanced.cleanupAbandonedVehiclesAfterMs'] = { type = 'number', min = 0, max = 3600000, integer = true },
    ['Advanced.abandonedVehicleSpeedThresholdMph'] = { type = 'number', min = 0.0, max = 20.0 },
    ['Advanced.debug'] = { type = 'boolean' },
    ['Advanced.showNPCCount'] = { type = 'boolean' },

    ['Events.enabled'] = { type = 'boolean' },
    ['Events.onPlayerEnterVehicle'] = { type = 'boolean' },
    ['Events.onPlayerExitVehicle'] = { type = 'boolean' },
    ['Events.onNPCSpawn'] = { type = 'boolean' },

    ['Blacklist.enabled'] = { type = 'boolean' },
    ['Whitelist.enabled'] = { type = 'boolean' },
})

local function splitPath(path)
    local parts = {}
    for part in string.gmatch(path, '[^.]+') do
        parts[#parts + 1] = part
    end
    return parts
end

local function normalizePanelPath(path)
    if type(path) == 'string' then
        local parts = splitPath(path)
        if #parts == 0 then
            return nil
        end
        return path, parts
    end

    if type(path) == 'table' then
        if #path == 0 then
            return nil
        end

        local parts = {}
        for i = 1, #path do
            if type(path[i]) ~= 'string' or path[i] == '' then
                return nil
            end
            parts[i] = path[i]
        end

        return table.concat(parts, '.'), parts
    end

    return nil
end

local function getValueAtPath(root, path)
    local node = root
    local parts = splitPath(path)
    for i = 1, #parts do
        if type(node) ~= 'table' then
            return nil
        end
        node = node[parts[i]]
    end
    return node
end

local function setValueAtPath(root, path, value)
    local node = root
    local parts = splitPath(path)
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(node[key]) ~= 'table' then
            node[key] = {}
        end
        node = node[key]
    end
    node[parts[#parts]] = value
end

local function clamp(value, minV, maxV)
    if value < minV then return minV end
    if value > maxV then return maxV end
    return value
end

local function validatePanelValue(path, value)
    local rule = PANEL_EDITABLE_PATHS[path]
    if not rule then
        return false, 'path_not_allowed'
    end

    if rule.type == 'boolean' then
        if type(value) ~= 'boolean' then
            return false, 'invalid_type'
        end
        return true, value
    end

    if rule.type == 'number' then
        if type(value) ~= 'number' then
            return false, 'invalid_type'
        end

        local out = clamp(value, rule.min, rule.max)
        if rule.integer then
            out = math.floor(out + 0.5)
        end

        return true, out
    end

    if rule.type == 'enum' then
        if type(value) ~= 'string' or not rule.values[value] then
            return false, 'invalid_value'
        end
        return true, value
    end

    return false, 'invalid_rule'
end

local function reloadConfigFromDisk()
    local ok, err = CBKAI_LoadLegacyConfig()
    if not ok then
        return false, err
    end

    local normalized = normalizeConfig(deepCopy(Config))
    applyServerConfig(normalized)
    return true
end

CBKAI.ConfigSync = {
    GetConfig = function()
        return syncState.config
    end,
    GetRevision = function()
        return syncState.revision
    end,
    SendFullConfig = sendFullConfig,
    ApplyServerConfig = function(config)
        applyServerConfig(normalizeConfig(config))
    end,
    ReloadFromDisk = reloadConfigFromDisk,
}

RegisterNetEvent('cbk_ai:sv:requestInit', function()
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'requestInit', Config.Security.requestInitMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        return
    end

    sendFullConfig(source)
end)

local function handlePanelOpenRequest(source)
    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return false
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelOpenDenied', source, Config.Locale.invalid_permission)
        return false
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelOpenDenied', source, Config.Locale.panel_locked or 'Panel locked by another admin')
        return false
    end

    acquirePanelLock(source)

    sendFullConfig(source)
    sendPanelProfileList(source)
    TriggerClientEvent('cbk_ai:cl:panelOpen', source, {
        revision = syncState.revision,
        lockOwner = getLockOwnerLabel(),
        profiles = listPanelProfiles(),
    })
    return true
end

RegisterNetEvent('cbk_ai:sv:panelOpenRequest', function()
    local source = source
    handlePanelOpenRequest(source)
end)

RegisterNetEvent('cbk_ai:sv:panelSetValue', function(payload)
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'panel_locked' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelSetValue', Config.Security.panelSetMaxCalls or 60, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    if type(payload) ~= 'table' or not CBKAI.Permissions.IsPayloadSafe(payload) then
        CBKAI.Permissions.RegisterSecurityStat('unsafePayload')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'invalid_payload' })
        return
    end


    local path = payload.path
    local value = payload.value

    local normalizedPath, pathTable = normalizePanelPath(path)
    if not normalizedPath or not isNuiPathAllowed(pathTable) then
        CBKAI.Permissions.RegisterSecurityStat('invalidPayload')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'invalid_path' })
        return
    end

    local ok, normalizedValueOrErr = validatePanelValue(normalizedPath, value)
    if not ok then
        CBKAI.Permissions.RegisterSecurityStat('invalidPayload')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = normalizedValueOrErr })
        return
    end

    local nextConfig = deepCopy(syncState.config)
    local previousValue = getValueAtPath(syncState.config, normalizedPath)
    setValueAtPath(nextConfig, normalizedPath, normalizedValueOrErr)
    nextConfig = normalizeConfig(nextConfig)

    if deepEqual(syncState.config, nextConfig) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, {
            ok = true,
            revision = syncState.revision,
            path = normalizedPath,
            value = getValueAtPath(syncState.config, normalizedPath),
        })
        return
    end

    applyServerConfig(nextConfig)
    local updatedValue = getValueAtPath(syncState.config, normalizedPath)
    auditPanelEvent(source, 'setValue', ('path=%s old=%s new=%s'):format(normalizedPath, stringifyAuditValue(previousValue), stringifyAuditValue(updatedValue)))

    TriggerClientEvent('cbk_ai:cl:panelAck', source, {
        ok = true,
        revision = syncState.revision,
        path = normalizedPath,
        value = updatedValue,
    })
end)

RegisterNetEvent('cbk_ai:sv:panelProfileListRequest', function()
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        return
    end

    if not canUsePanelLock(source) then
        return
    end

    sendPanelProfileList(source)
end)

RegisterNetEvent('cbk_ai:sv:panelClose', function()
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        return
    end

    if releasePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
            tone = 'ok',
            message = 'Panel lock released.'
        })
    end
end)

RegisterNetEvent('cbk_ai:sv:panelSaveProfile', function()
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'panel_locked' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelAdminAction', Config.Security.panelAdminActionMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    local ok, err = savePanelProfile(syncState.config, getPlayerNameSafe(source))
    if not ok then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = err or 'save_failed' })
        return
    end

    sendPanelProfileList(source)
    auditPanelEvent(source, 'saveProfile', 'profile=runtime')

    TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
        tone = 'ok',
        message = 'Runtime profile saved.'
    })
end)

RegisterNetEvent('cbk_ai:sv:panelSaveNamedProfile', function(payload)
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'panel_locked' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelAdminAction', Config.Security.panelAdminActionMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    if type(payload) ~= 'table' or not CBKAI.Permissions.IsPayloadSafe(payload) then
        CBKAI.Permissions.RegisterSecurityStat('unsafePayload')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'invalid_payload' })
        return
    end

    local ok, safeNameOrErr = saveNamedPanelProfile(payload.name, syncState.config, getPlayerNameSafe(source))
    if not ok then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = safeNameOrErr or 'save_failed' })
        return
    end

    sendPanelProfileList(source)
    auditPanelEvent(source, 'saveNamedProfile', ('profile=%s'):format(safeNameOrErr))
    TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
        tone = 'ok',
        message = ('Profile saved: %s'):format(safeNameOrErr)
    })
end)

RegisterNetEvent('cbk_ai:sv:panelLoadProfile', function()
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'panel_locked' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelAdminAction', Config.Security.panelAdminActionMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    local ok, profileOrErr = loadPanelProfile(getPlayerNameSafe(source))
    if not ok then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = profileOrErr or 'load_failed' })
        return
    end

    local normalized = normalizeConfig(deepCopy(profileOrErr))
    applyServerConfig(normalized)
    sendPanelProfileList(source)
    auditPanelEvent(source, 'loadProfile', 'profile=runtime')

    TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
        tone = 'ok',
        message = 'Runtime profile loaded.'
    })
end)

RegisterNetEvent('cbk_ai:sv:panelLoadNamedProfile', function(payload)
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'panel_locked' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelAdminAction', Config.Security.panelAdminActionMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    if type(payload) ~= 'table' or not CBKAI.Permissions.IsPayloadSafe(payload) then
        CBKAI.Permissions.RegisterSecurityStat('unsafePayload')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'invalid_payload' })
        return
    end

    local ok, profileOrErr, safeName = loadNamedPanelProfile(payload.name, getPlayerNameSafe(source))
    if not ok then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = profileOrErr or 'load_failed' })
        return
    end

    local normalized = normalizeConfig(deepCopy(profileOrErr))
    applyServerConfig(normalized)
    sendPanelProfileList(source)
    auditPanelEvent(source, 'loadNamedProfile', ('profile=%s'):format(safeName))

    TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
        tone = 'ok',
        message = ('Profile loaded: %s'):format(safeName)
    })
end)

RegisterNetEvent('cbk_ai:sv:panelDeleteProfile', function(payload)
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if not canUsePanelLock(source) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'panel_locked' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelAdminAction', Config.Security.panelAdminActionMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    if type(payload) ~= 'table' or not CBKAI.Permissions.IsPayloadSafe(payload) then
        CBKAI.Permissions.RegisterSecurityStat('unsafePayload')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'invalid_payload' })
        return
    end

    local ok, safeNameOrErr = deleteNamedPanelProfile(payload.name)
    if not ok then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = safeNameOrErr or 'delete_failed' })
        return
    end

    sendPanelProfileList(source)
    auditPanelEvent(source, 'deleteNamedProfile', ('profile=%s'):format(safeNameOrErr))
    TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
        tone = 'ok',
        message = ('Profile deleted: %s'):format(safeNameOrErr)
    })
end)

RegisterNetEvent('cbk_ai:sv:panelReleaseLock', function()
    local source = source

    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if not CBKAI.Permissions.HasAdminPermission(source) then
        CBKAI.Permissions.RegisterSecurityStat('permissionDenied')
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'permission_denied' })
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'panelAdminAction', Config.Security.panelAdminActionMaxCalls or 12, Config.Security.rateLimitWindowMs or 5000) then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, { ok = false, reason = 'rate_limited' })
        return
    end

    if panelLock.owner ~= source then
        TriggerClientEvent('cbk_ai:cl:panelAck', source, {
            ok = false,
            reason = ('lock_owner_%s'):format(getLockOwnerLabel())
        })
        return
    end

    releasePanelLock(source)
    auditPanelEvent(source, 'releaseLock', '')
    TriggerClientEvent('cbk_ai:cl:panelNotice', source, {
        tone = 'ok',
        message = 'Panel lock released.'
    })
end)

local function sendChat(source, message, color)
    if source == 0 then
        print(('^2[CBK AI]^7 %s'):format(message))
        return
    end

    TriggerClientEvent('chat:addMessage', source, {
        color = color or { 0, 255, 0 },
        multiline = true,
        args = { 'AI Controller', message }
    })
end

if Config.Commands.enabled then
    RegisterCommand(Config.Commands.reloadCommand, function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local reloaded, err = CBKAI.ConfigSync.ReloadFromDisk()
        if not reloaded then
            sendChat(source, ('Config reload failed: %s'):format(err or 'unknown error'), { 255, 0, 0 })
            return
        end

        sendChat(source, 'Configuration reloaded and synchronized.', { 0, 255, 0 })
    end, false)

    RegisterCommand(Config.Commands.toggleCommand, function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local nextConfig = deepCopy(syncState.config)
        nextConfig.EnableNPCs = not nextConfig.EnableNPCs
        CBKAI.ConfigSync.ApplyServerConfig(nextConfig)

        sendChat(source, ('NPCs have been %s.'):format(nextConfig.EnableNPCs and 'enabled' or 'disabled'), { 0, 255, 0 })
    end, false)

    RegisterCommand(Config.Commands.panelSaveCommand or 'cbkpanelsave', function(source, args)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        if source ~= 0 and not canUsePanelLock(source) then
            sendChat(source, Config.Locale.panel_locked or 'Panel lock is held by another admin.', { 255, 0, 0 })
            return
        end

        local requestedName = args and args[1]
        local saved, safeNameOrErr
        local adminName = getPlayerNameSafe(source)
        if requestedName then
            saved, safeNameOrErr = saveNamedPanelProfile(requestedName, syncState.config, adminName)
        else
            saved, safeNameOrErr = savePanelProfile(syncState.config, adminName)
        end

        if not saved then
            sendChat(source, ('Panel profile save failed: %s'):format(safeNameOrErr or 'unknown error'), { 255, 0, 0 })
            return
        end

        local profileName = requestedName and safeNameOrErr or 'runtime'
        sendChat(source, ('Panel profile saved: %s'):format(profileName), { 0, 255, 0 })
        auditPanelEvent(source, 'commandSaveProfile', ('profile=%s'):format(profileName))
    end, false)

    RegisterCommand(Config.Commands.panelLoadCommand or 'cbkpanelload', function(source, args)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        if source ~= 0 and not canUsePanelLock(source) then
            sendChat(source, Config.Locale.panel_locked or 'Panel lock is held by another admin.', { 255, 0, 0 })
            return
        end

        local requestedName = args and args[1]
        local loaded, profileOrErr, safeName = requestedName and loadNamedPanelProfile(requestedName, getPlayerNameSafe(source)) or loadPanelProfile(getPlayerNameSafe(source))
        if not loaded then
            sendChat(source, ('Panel profile load failed: %s'):format(profileOrErr or 'unknown error'), { 255, 0, 0 })
            return
        end

        local normalized = normalizeConfig(deepCopy(profileOrErr))
        applyServerConfig(normalized)
        local profileName = safeName or 'runtime'
        sendChat(source, ('Panel profile loaded and synchronized: %s'):format(profileName), { 0, 255, 0 })
        auditPanelEvent(source, 'commandLoadProfile', ('profile=%s'):format(profileName))
    end, false)

    RegisterCommand(Config.Commands.panelUnlockCommand or 'cbkpanelunlock', function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        if source ~= 0 and panelLock.owner ~= 0 and panelLock.owner ~= source then
            sendChat(source, ('Panel lock is held by %s.'):format(getLockOwnerLabel()), { 255, 0, 0 })
            return
        end

        panelLock.owner = 0
        panelLock.ownerName = nil
        panelLock.acquiredAt = 0
        sendChat(source, 'Panel lock released.', { 0, 255, 0 })
        auditPanelEvent(source, 'commandReleaseLock', '')
    end, false)

    RegisterCommand(Config.Commands.validateCommand or 'npcvalidate', function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local candidate = deepCopy(syncState.config)
        local normalized = normalizeConfig(deepCopy(candidate))
        if deepEqual(candidate, normalized) then
            sendChat(source, 'Config validation passed: no normalized changes required.', { 0, 255, 0 })
            return
        end

        sendChat(source, 'Config validation: normalized values differ from current runtime state.', { 255, 255, 0 })
    end, false)

    RegisterCommand(Config.Commands.statusCommand or 'npcstatus', function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local c = syncState.config
        local statusMessage = ('Revision: %d | Mode: ambient-only | NPCs: %s | UpdateInterval: %d | MaxDistance: %.1f | StandaloneAmbient: %s'):format(
            syncState.revision,
            tostring(c.EnableNPCs),
            c.Advanced.updateInterval,
            c.Advanced.maxNPCDistance,
            tostring(c.Advanced.standaloneAmbientControl ~= false)
        )

        if source ~= 0 and CBKAI.NPCController and CBKAI.NPCController.GetRuntimeReport then
            local report = CBKAI.NPCController.GetRuntimeReport(source)
            if report and (GetGameTimer() - report.updatedAt) <= 15000 then
                statusMessage = ('%s | Nearby ambient peds=%d vehicles=%d | Client revision=%d'):format(
                    statusMessage,
                    report.nearbyAmbientPeds,
                    report.nearbyAmbientVehicles,
                    report.revision
                )
            else
                statusMessage = statusMessage .. ' | No recent client runtime report'
            end
        end

        sendChat(source, statusMessage, { 0, 200, 255 })
    end, false)
end

AddEventHandler('playerDropped', function()
    if panelLock.owner == source then
        panelLock.owner = 0
        panelLock.ownerName = nil
        panelLock.acquiredAt = 0
    end
end)

local bootConfig = normalizeConfig(deepCopy(Config))
applyServerConfig(bootConfig)
if not hasPersistedRuntimeProfile() then
    savePanelProfile(syncState.config, 'system')
end
