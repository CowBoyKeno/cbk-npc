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

local function resolveLog()
    if type(CBKAI.Log) == 'table' then
        return CBKAI.Log
    end
    local loaded = safeRequire('log') or safeRequire('shared.log')
    if type(loaded) == 'table' then
        CBKAI.Log = loaded
        return loaded
    end
    local noop = function() end
    return {
        debug = noop,
        info = noop,
        warn = noop,
        error = noop,
        perfMarker = noop,
    }
end

local Log = resolveLog()
local Utils = resolveUtils()

local runtimeReports = {}

local TRAFFIC_CONTEXT_RADIUS = 150.0
local TRAFFIC_CONTEXT_CELL_SIZE = 75.0

local trafficContextTelemetry = {
    windowStartedAt = 0,
    cycles = 0,
    indexedOnFootPlayers = 0,
    targetedPlayers = 0,
    totalAnchors = 0,
    maxAnchorsInPayload = 0,
}

local function nowMs()
    return GetGameTimer()
end

trafficContextTelemetry.windowStartedAt = nowMs()

local clamp = Utils.clamp

local function isTruthyConvar(name)
    local value = string.lower(GetConvar(name, 'false'))
    return value == 'true' or value == '1' or value == 'yes' or value == 'on'
end

local function isTelemetryLoggingEnabled()
    return isTruthyConvar('cbk_npc_telemetry')
        or isTruthyConvar('cbk_npc_debug')
        or (type(Config) == 'table' and type(Config.Advanced) == 'table' and Config.Advanced.debug == true)
end

local function sanitizeMetric(value, maxValue)
    local numeric = math.floor(tonumber(value) or 0)
    return clamp(numeric, 0, maxValue)
end

local function sanitizeVehicleNetIds(values, maxCount)
    if type(values) ~= 'table' then
        return {}
    end

    local sanitized = {}
    local seen = {}
    local limit = math.max(0, math.floor(tonumber(maxCount) or 0))

    for i = 1, #values do
        if #sanitized >= limit then
            break
        end

        local netId = sanitizeMetric(values[i], 2147483647)
        if netId > 0 and not seen[netId] then
            seen[netId] = true
            sanitized[#sanitized + 1] = netId
        end
    end

    return sanitized
end

local function aggregateRuntimeReports(maxAgeMs)
    local summary = {
        clients = 0,
        nearbyAmbientPeds = 0,
        nearbyAmbientVehicles = 0,
        nearbyManagedPeds = 0,
        nearbyManagedVehicles = 0,
    }

    local now = nowMs()
    for _, report in pairs(runtimeReports) do
        if report and (now - report.updatedAt) <= maxAgeMs then
            summary.clients = summary.clients + 1
            summary.nearbyAmbientPeds = summary.nearbyAmbientPeds + (report.nearbyAmbientPeds or 0)
            summary.nearbyAmbientVehicles = summary.nearbyAmbientVehicles + (report.nearbyAmbientVehicles or 0)
            summary.nearbyManagedPeds = summary.nearbyManagedPeds + (report.nearbyManagedPeds or 0)
            summary.nearbyManagedVehicles = summary.nearbyManagedVehicles + (report.nearbyManagedVehicles or 0)
        end
    end

    return summary
end

local function aggregateProtectedVehicleNetIds(maxAgeMs)
    local protected = {}
    local seen = {}
    local now = nowMs()

    for _, report in pairs(runtimeReports) do
        if report and (now - report.updatedAt) <= maxAgeMs then
            local vehicleIds = report.protectedVehicleNetIds or {}
            for i = 1, #vehicleIds do
                local netId = vehicleIds[i]
                if netId and netId > 0 and not seen[netId] then
                    seen[netId] = true
                    protected[#protected + 1] = netId
                end
            end
        end
    end

    return protected
end

local function sendChat(source, message, color)
    if source == 0 then
        print(('^2[CBK AI]^7 %s'):format(message))
        return
    end

    TriggerClientEvent('chat:addMessage', source, {
        color = color or { 0, 255, 255 },
        multiline = true,
        args = { 'AI Controller', message }
    })
end

local function gridKey(cellX, cellY)
    return ('%d:%d'):format(cellX, cellY)
end

local function buildOnFootSpatialIndex(players)
    local index = {}

    for i = 1, #players do
        local source = tonumber(players[i])
        if source then
            local ped = GetPlayerPed(source)
            if ped ~= 0 and DoesEntityExist(ped) and GetVehiclePedIsIn(ped, false) == 0 then
                local coords = GetEntityCoords(ped)
                local cellX = math.floor(coords.x / TRAFFIC_CONTEXT_CELL_SIZE)
                local cellY = math.floor(coords.y / TRAFFIC_CONTEXT_CELL_SIZE)
                local key = gridKey(cellX, cellY)

                if not index[key] then
                    index[key] = {}
                end

                index[key][#index[key] + 1] = {
                    source = source,
                    coords = coords,
                }
            end
        end
    end

    return index
end

local function buildTrafficContextForPlayer(targetSource, targetCoords, index)
    local pedestrianAnchors = {}
    local cellX = math.floor(targetCoords.x / TRAFFIC_CONTEXT_CELL_SIZE)
    local cellY = math.floor(targetCoords.y / TRAFFIC_CONTEXT_CELL_SIZE)
    local cellRadius = math.ceil(TRAFFIC_CONTEXT_RADIUS / TRAFFIC_CONTEXT_CELL_SIZE)

    for dx = -cellRadius, cellRadius do
        for dy = -cellRadius, cellRadius do
            local key = gridKey(cellX + dx, cellY + dy)
            local bucket = index[key]

            if bucket then
                for i = 1, #bucket do
                    local anchor = bucket[i]
                    if anchor.source ~= targetSource and #(anchor.coords - targetCoords) <= TRAFFIC_CONTEXT_RADIUS then
                        pedestrianAnchors[#pedestrianAnchors + 1] = {
                            x = anchor.coords.x,
                            y = anchor.coords.y,
                            z = anchor.coords.z,
                        }
                    end
                end
            end
        end
    end

    return {
        pedestrianAnchors = pedestrianAnchors,
        updatedAt = nowMs(),
    }
end

local function getIndexedPlayerCount(index)
    local total = 0
    for _, bucket in pairs(index) do
        total = total + #bucket
    end
    return total
end

local function recordTrafficContextCycle(indexedOnFootPlayers, targetedPlayers, totalAnchors, maxAnchorsInPayload)
    trafficContextTelemetry.cycles = trafficContextTelemetry.cycles + 1
    trafficContextTelemetry.indexedOnFootPlayers = trafficContextTelemetry.indexedOnFootPlayers + indexedOnFootPlayers
    trafficContextTelemetry.targetedPlayers = trafficContextTelemetry.targetedPlayers + targetedPlayers
    trafficContextTelemetry.totalAnchors = trafficContextTelemetry.totalAnchors + totalAnchors
    if maxAnchorsInPayload > trafficContextTelemetry.maxAnchorsInPayload then
        trafficContextTelemetry.maxAnchorsInPayload = maxAnchorsInPayload
    end
end

local function getTrafficContextTelemetrySnapshot(reset)
    local cycles = math.max(trafficContextTelemetry.cycles, 1)
    local elapsedMs = math.max(1, nowMs() - (trafficContextTelemetry.windowStartedAt or nowMs()))
    local snapshot = {
        cycles = trafficContextTelemetry.cycles,
        elapsedMs = elapsedMs,
        avgIndexedOnFootPlayers = trafficContextTelemetry.indexedOnFootPlayers / cycles,
        avgTargetedPlayers = trafficContextTelemetry.targetedPlayers / cycles,
        avgAnchorsPerPayload = trafficContextTelemetry.totalAnchors / math.max(trafficContextTelemetry.targetedPlayers, 1),
        avgAnchorsPerCycle = trafficContextTelemetry.totalAnchors / cycles,
        maxAnchorsInPayload = trafficContextTelemetry.maxAnchorsInPayload,
    }

    if reset then
        trafficContextTelemetry.windowStartedAt = nowMs()
        trafficContextTelemetry.cycles = 0
        trafficContextTelemetry.indexedOnFootPlayers = 0
        trafficContextTelemetry.targetedPlayers = 0
        trafficContextTelemetry.totalAnchors = 0
        trafficContextTelemetry.maxAnchorsInPayload = 0
    end

    return snapshot
end

CBKAI.NPCController = {
    ClearManagedEntities = function()
        return 0
    end,
    Count = function()
        return 0
    end,
    GetRuntimeReport = function(source)
        return runtimeReports[source]
    end,
    GetAggregateRuntime = function(maxAgeMs)
        return aggregateRuntimeReports(maxAgeMs or 15000)
    end,
    GetTrafficContextTelemetry = function(reset)
        return getTrafficContextTelemetrySnapshot(reset == true)
    end,
}

RegisterNetEvent('cbk_ai:sv:runtimeReport', function(payload)
    local source = source
    if not CBKAI.Permissions.ValidatePlayerSource(source) then
        CBKAI.Permissions.RegisterSecurityStat('invalidSource')
        return
    end

    if CBKAI.Permissions.IsRateLimited(source, 'runtimeReport', Config.Security.runtimeReportMaxCalls or 24, Config.Security.rateLimitWindowMs or 5000) then
        return
    end

    if type(payload) ~= 'table' or not CBKAI.Permissions.IsPayloadSafe(payload) then
        CBKAI.Permissions.RegisterSecurityStat('invalidPayload')
        return
    end

    runtimeReports[source] = {
        nearbyAmbientPeds = sanitizeMetric(payload.nearbyAmbientPeds, 4096),
        nearbyAmbientVehicles = sanitizeMetric(payload.nearbyAmbientVehicles, 4096),
        nearbyManagedPeds = 0,
        nearbyManagedVehicles = 0,
        standaloneAmbientControl = payload.standaloneAmbientControl == true,
        revision = sanitizeMetric(payload.revision, 1000000),
        protectedVehicleNetIds = sanitizeVehicleNetIds(payload.protectedVehicleNetIds, 8),
        updatedAt = nowMs(),
    }
end)

if Config.Commands.enabled then
    RegisterCommand(Config.Commands.clearCommand, function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local protectedVehicleNetIds = aggregateProtectedVehicleNetIds(30000)
        runtimeReports = {}
        TriggerClientEvent('cbk_ai:cl:clearWorld', -1, {
            protectedVehicleNetIds = protectedVehicleNetIds,
        })
        sendChat(source, ('Clear request broadcast to all clients. Ambient NPCs and vehicles are being purged while protecting %d player vehicle(s).'):format(#protectedVehicleNetIds), { 255, 255, 0 })
    end, false)

    RegisterCommand(Config.Commands.countCommand, function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local maxAgeMs = 15000
        if source == 0 then
            local summary = aggregateRuntimeReports(maxAgeMs)
            local output = ('Recent client reports=%d | summed ambient: peds=%d vehicles=%d'):format(
                summary.clients,
                summary.nearbyAmbientPeds,
                summary.nearbyAmbientVehicles
            )
            sendChat(source, output, { 0, 255, 255 })
            return
        end

        local report = runtimeReports[source]
        if report and (nowMs() - report.updatedAt) <= maxAgeMs then
            local output = ('Nearby ambient: peds=%d vehicles=%d | client revision=%d'):format(
                report.nearbyAmbientPeds,
                report.nearbyAmbientVehicles,
                report.revision or 0
            )
            sendChat(source, output, { 0, 255, 255 })
        else
            sendChat(source, 'No recent client runtime report.', { 255, 255, 0 })
        end
    end, false)

    RegisterCommand(Config.Commands.trafficStatsCommand or 'npctrafficstats', function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local snapshot = CBKAI.NPCController.GetTrafficContextTelemetry(false)
        local output = ('Traffic telemetry | cycles=%d windowMs=%d avgIndexedOnFoot=%.1f avgTargets=%.1f avgAnchorsPayload=%.2f avgAnchorsCycle=%.1f maxAnchorsPayload=%d'):format(
            snapshot.cycles,
            snapshot.elapsedMs,
            snapshot.avgIndexedOnFootPlayers,
            snapshot.avgTargetedPlayers,
            snapshot.avgAnchorsPerPayload,
            snapshot.avgAnchorsPerCycle,
            snapshot.maxAnchorsInPayload
        )

        sendChat(source, output, { 0, 200, 255 })
    end, false)

    RegisterCommand(Config.Commands.trafficStatsResetCommand or 'npctrafficstatsreset', function(source)
        local ok, message = CBKAI.Permissions.CanRunProtectedCommand(source)
        if not ok then
            sendChat(source, message, { 255, 0, 0 })
            return
        end

        local snapshot = CBKAI.NPCController.GetTrafficContextTelemetry(true)
        local output = ('Traffic telemetry window reset | prior cycles=%d windowMs=%d avgAnchorsPayload=%.2f maxAnchorsPayload=%d'):format(
            snapshot.cycles,
            snapshot.elapsedMs,
            snapshot.avgAnchorsPerPayload,
            snapshot.maxAnchorsInPayload
        )

        sendChat(source, output, { 255, 255, 0 })
    end, false)
end

AddEventHandler('playerDropped', function()
    runtimeReports[source] = nil
end)

CreateThread(function()
    while true do
        local t0 = GetGameTimer()
        local players = GetPlayers()
        local onFootSpatialIndex = buildOnFootSpatialIndex(players)
        local indexedOnFootPlayers = getIndexedPlayerCount(onFootSpatialIndex)
        local targetedPlayers = 0
        local totalAnchors = 0
        local maxAnchorsInPayload = 0

        for i = 1, #players do
            local source = tonumber(players[i])
            if source then
                local targetPed = GetPlayerPed(source)
                if targetPed ~= 0 and DoesEntityExist(targetPed) then
                    local context = buildTrafficContextForPlayer(source, GetEntityCoords(targetPed), onFootSpatialIndex)
                    local anchorCount = #context.pedestrianAnchors
                    targetedPlayers = targetedPlayers + 1
                    totalAnchors = totalAnchors + anchorCount
                    if anchorCount > maxAnchorsInPayload then
                        maxAnchorsInPayload = anchorCount
                    end
                    TriggerClientEvent('cbk_ai:cl:trafficContext', source, context)
                end
            end
        end

        recordTrafficContextCycle(indexedOnFootPlayers, targetedPlayers, totalAnchors, maxAnchorsInPayload)

        local t1 = GetGameTimer()
        Log.perfMarker(('TrafficContextLoop: %d players, %d ms'), #players, t1 - t0)

        Wait(500)
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Security.telemetryIntervalMs or 300000)
        local snapshot = getTrafficContextTelemetrySnapshot(true)
        if snapshot.cycles > 0 and isTelemetryLoggingEnabled() then
            print(('^3[CBK AI Traffic]^7 cycles=%d windowMs=%d avgIndexedOnFoot=%.1f avgTargets=%.1f avgAnchorsPayload=%.2f avgAnchorsCycle=%.1f maxAnchorsPayload=%d'):format(
                snapshot.cycles,
                snapshot.elapsedMs,
                snapshot.avgIndexedOnFootPlayers,
                snapshot.avgTargetedPlayers,
                snapshot.avgAnchorsPerPayload,
                snapshot.avgAnchorsPerCycle,
                snapshot.maxAnchorsInPayload
            ))
        end
    end
end)
