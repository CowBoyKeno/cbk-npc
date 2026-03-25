CBKAI = CBKAI or {}

local permissionState = {
    requests = {},
    commandLastUse = {},
    securityStats = {
        invalidSource = 0,
        invalidPayload = 0,
        unsafePayload = 0,
        permissionDenied = 0,
        commandRateLimited = 0,
        eventRateLimited = {},
    }
}

local function isTruthyConvar(name)
    local value = string.lower(GetConvar(name, 'false'))
    return value == 'true' or value == '1' or value == 'yes' or value == 'on'
end

local function isTelemetryLoggingEnabled()
    return isTruthyConvar('cbk_npc_telemetry')
        or isTruthyConvar('cbk_npc_debug')
        or (type(Config) == 'table' and type(Config.Advanced) == 'table' and Config.Advanced.debug == true)
end

local function countTableNodes(value, depth, seen, maxDepth, maxNodes)
    if type(value) ~= 'table' then
        return 1
    end

    if depth > maxDepth then
        return maxNodes + 1
    end

    if seen[value] then
        return 0
    end

    seen[value] = true

    local total = 1
    for k, v in pairs(value) do
        total = total + countTableNodes(k, depth + 1, seen, maxDepth, maxNodes)
        if total > maxNodes then
            return total
        end

        total = total + countTableNodes(v, depth + 1, seen, maxDepth, maxNodes)
        if total > maxNodes then
            return total
        end
    end

    return total
end

local function isPayloadSafe(payload)
    if type(payload) ~= 'table' then
        return false
    end

    local maxDepth = Config.Security.maxPayloadDepth or 12
    local maxNodes = Config.Security.maxPayloadNodes or 2500
    local nodes = countTableNodes(payload, 0, {}, maxDepth, maxNodes)
    return nodes <= maxNodes
end

local function getPlayerNameSafe(source)
    local ok, name = pcall(GetPlayerName, source)
    if not ok then return nil end
    return name
end

local function normalizeIdentifier(identifier)
    if type(identifier) ~= 'string' then
        return nil
    end

    local normalized = string.lower(identifier)
    normalized = normalized:gsub('^identifier%.', '')
    return normalized
end

local function isIdentifierAuthorized(source)
    local allowed = (Config.Security and Config.Security.adminIdentifiers) or {}
    if #allowed == 0 then
        return false
    end

    local identifiers = GetPlayerIdentifiers(source)
    if type(identifiers) ~= 'table' then
        return false
    end

    for i = 1, #identifiers do
        local playerIdentifier = normalizeIdentifier(identifiers[i])
        if playerIdentifier then
            for j = 1, #allowed do
                if playerIdentifier == normalizeIdentifier(allowed[j]) then
                    return true
                end
            end
        end
    end

    return false
end

local function hasAcePermission(source)
    if Config.Security and Config.Security.allowAcePermissions == false then
        return false
    end

    if IsPlayerAceAllowed(source, 'command.npccontrol') then
        return true
    end

    local permissionLevel = Config.Commands.permissionLevel or 'admin'
    if type(permissionLevel) ~= 'string' or permissionLevel == '' then
        return false
    end

    return IsPlayerAceAllowed(source, permissionLevel)
end

local function hasAdminPermission(source)
    if source == 0 then
        return Config.Security == nil or Config.Security.allowConsole ~= false
    end

    if not Config.Commands.requirePermission then
        return true
    end

    if hasAcePermission(source) then
        return true
    end

    return isIdentifierAuthorized(source)
end

local function validatePlayerSource(source)
    return type(source) == 'number' and source > 0 and getPlayerNameSafe(source) ~= nil
end

local function registerSecurityStat(key)
    if permissionState.securityStats[key] ~= nil then
        permissionState.securityStats[key] = permissionState.securityStats[key] + 1
    end
end

local function registerRateLimitStat(key)
    local stats = permissionState.securityStats.eventRateLimited
    stats[key] = (stats[key] or 0) + 1
end

local function isRateLimited(source, key, maxCalls, windowMs)
    local now = GetGameTimer()
    permissionState.requests[source] = permissionState.requests[source] or {}

    local bucket = permissionState.requests[source][key]
    if not bucket or (now - bucket.startedAt) > windowMs then
        permissionState.requests[source][key] = {
            startedAt = now,
            count = 1,
        }
        return false
    end

    bucket.count = bucket.count + 1
    if bucket.count > maxCalls then
        registerRateLimitStat(key)
        return true
    end

    return false
end

local function isCommandRateLimited(source)
    if source == 0 then
        return false
    end

    local now = GetGameTimer()
    local lastUse = permissionState.commandLastUse[source] or 0
    if (now - lastUse) < (Config.Security.commandCooldownMs or 1000) then
        registerSecurityStat('commandRateLimited')
        return true
    end

    permissionState.commandLastUse[source] = now
    return false
end

local function canRunProtectedCommand(source)
    if not hasAdminPermission(source) then
        registerSecurityStat('permissionDenied')
        return false, Config.Locale.invalid_permission
    end

    if isCommandRateLimited(source) then
        return false, 'Command rate limited. Try again in a moment.'
    end

    return true
end

local function formatTelemetrySummary()
    local stat = permissionState.securityStats
    local eventStats = stat.eventRateLimited

    return string.format(
        'invalidSource=%d invalidPayload=%d unsafePayload=%d permissionDenied=%d commandRateLimited=%d rateLimited(init=%d,runtime=%d)',
        stat.invalidSource,
        stat.invalidPayload,
        stat.unsafePayload,
        stat.permissionDenied,
        stat.commandRateLimited,
        eventStats.requestInit or 0,
        eventStats.runtimeReport or 0
    )
end

local function hasTelemetryEvents()
    local stat = permissionState.securityStats
    if stat.invalidSource > 0 or stat.invalidPayload > 0 or stat.unsafePayload > 0 or stat.permissionDenied > 0 or stat.commandRateLimited > 0 then
        return true
    end

    for _, count in pairs(stat.eventRateLimited) do
        if count > 0 then
            return true
        end
    end

    return false
end

local function resetTelemetry()
    permissionState.securityStats = {
        invalidSource = 0,
        invalidPayload = 0,
        unsafePayload = 0,
        permissionDenied = 0,
        commandRateLimited = 0,
        eventRateLimited = {},
    }
end

local function cleanupSource(source)
    permissionState.requests[source] = nil
    permissionState.commandLastUse[source] = nil
end

CBKAI.Permissions = {
    HasAdminPermission = hasAdminPermission,
    ValidatePlayerSource = validatePlayerSource,
    IsRateLimited = isRateLimited,
    CanRunProtectedCommand = canRunProtectedCommand,
    RegisterSecurityStat = registerSecurityStat,
    FormatTelemetrySummary = formatTelemetrySummary,
    HasTelemetryEvents = hasTelemetryEvents,
    ResetTelemetry = resetTelemetry,
    CleanupSource = cleanupSource,
    IsPayloadSafe = isPayloadSafe,
}

AddEventHandler('playerDropped', function()
    CBKAI.Permissions.CleanupSource(source)
end)

CreateThread(function()
    while true do
        Wait(Config.Security.telemetryIntervalMs or 300000)
        if CBKAI.Permissions.HasTelemetryEvents() then
            if isTelemetryLoggingEnabled() then
                print(('^3[CBK AI Security]^7 %s'):format(CBKAI.Permissions.FormatTelemetrySummary()))
            end
            CBKAI.Permissions.ResetTelemetry()
        end
    end
end)
