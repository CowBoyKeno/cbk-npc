CBKAI = CBKAI or {}

local function deepCopy(value)
    return CBKAI_DeepCopy(value)
end

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

    config.VehicleSettings.trafficDensity = clamp(config.VehicleSettings.trafficDensity, 0.0, 1.0)
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

local bootConfig = normalizeConfig(deepCopy(Config))
applyServerConfig(bootConfig)
