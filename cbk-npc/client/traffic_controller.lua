CBKAI = CBKAI or {}

CBKAI.ClientState = CBKAI.ClientState or {
    config = Config,
    revision = 0,
    trafficContext = {
        pedestrianAnchors = {},
        receivedAt = 0,
    },
}

local speedLimitedVehicles = {}
local hornMutedVehicles = {}
local speechMutedDrivers = {}
local globalHornMutedVehicles = {}
local bypassTaskUntil = {}
local bubbleStuckSince = {}
local bypassSideLock = {}
local bypassPlan = {}
local hornNativeSupported = nil
local lastPlayerVehicle = 0
local lastPlayerVehicleExitAt = 0
local lastWantedStaticKey = nil
local lastVehicleSuppressionKey = nil
local lastSuppressionSweepAt = 0
local masterDisableStateApplied = false
local lastEnableNPCsState = nil

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
local clamp = Utils.clamp
local EntityGuards = CBKAI.ClientEntityGuards or {}

local function isAmbientVehicleEntity(vehicle)
    if type(EntityGuards.IsAmbientVehicle) == 'function' then
        return EntityGuards.IsAmbientVehicle(vehicle)
    end

    return vehicle ~= 0 and DoesEntityExist(vehicle) and not IsEntityAMissionEntity(vehicle)
end

local function suppressionMultiplier(level)
    if level == 'none' then return 1.0 end
    if level == 'low' then return 0.85 end
    if level == 'medium' then return 0.65 end
    if level == 'high' then return 0.45 end
    if level == 'maximum' then return 0.2 end
    return 0.65
end

local function setHornEnabledSafe(vehicle, enabled)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    if hornNativeSupported == false then
        return false
    end

    local ok = pcall(function()
        SetHornEnabled(vehicle, enabled)
    end)

    if not ok then
        hornNativeSupported = false
        return false
    end

    hornNativeSupported = true
    return true
end

local function resetVehicleEmergencyState(vehicle)
    if vehicle == 0 then
        return
    end

    local vehicleExists = DoesEntityExist(vehicle)

    if speedLimitedVehicles[vehicle] then
        if vehicleExists then
            SetVehicleMaxSpeed(vehicle, 0.0)
        end
        speedLimitedVehicles[vehicle] = nil
    end

    bypassTaskUntil[vehicle] = nil
    bubbleStuckSince[vehicle] = nil
    bypassSideLock[vehicle] = nil
    bypassPlan[vehicle] = nil

    local mutedDriver = speechMutedDrivers[vehicle]
    if mutedDriver then
        if DoesEntityExist(mutedDriver) then
            if CBKAI.ClientState.config.NPCBehavior.disableAmbientSpeech ~= true then
                StopPedSpeaking(mutedDriver, false)
            end
        end
        speechMutedDrivers[vehicle] = nil
    end

    if hornMutedVehicles[vehicle] then
        if vehicleExists then
            if not globalHornMutedVehicles[vehicle] then
                setHornEnabledSafe(vehicle, true)
            end
        end
        hornMutedVehicles[vehicle] = nil
    end

    if globalHornMutedVehicles[vehicle] and not vehicleExists then
        globalHornMutedVehicles[vehicle] = nil
    end
end

local function deleteVehicleSafely(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    if not isAmbientVehicleEntity(vehicle) then
        return
    end

    local timeout = GetGameTimer() + 250
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(vehicle)
        Wait(0)
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteEntity(vehicle)
end

local function isVehiclePlayerOccupied(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxPassengers - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then
            return true
        end
    end

    return false
end

local function updatePlayerVehicleTracking()
    local currentVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if currentVehicle ~= 0 and DoesEntityExist(currentVehicle) then
        lastPlayerVehicle = currentVehicle
        lastPlayerVehicleExitAt = GetGameTimer()
        return
    end

    if lastPlayerVehicle ~= 0 and not DoesEntityExist(lastPlayerVehicle) then
        lastPlayerVehicle = 0
        lastPlayerVehicleExitAt = 0
    end
end

local function isProtectedPlayerVehicle(vehicle, cfg, playerCoords)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    if isVehiclePlayerOccupied(vehicle) then
        return true
    end

    local settings = cfg.VehicleSettings or {}
    if settings.preservePlayerLastVehicle == false then
        return false
    end

    if vehicle ~= lastPlayerVehicle then
        return false
    end

    local now = GetGameTimer()
    local retentionMs = settings.playerVehicleProtectionMs or 600000
    if (now - lastPlayerVehicleExitAt) > retentionMs then
        return false
    end

    local maxDistance = settings.playerVehicleProtectionDistance or 300.0
    return #(GetEntityCoords(vehicle) - playerCoords) <= maxDistance
end

local function applyWantedSettings(cfg)
    local wanted = cfg.WantedSystem or {}
    local npcBehavior = cfg.NPCBehavior or {}
    local crimeReportsEnabled = wanted.npcReportCrimes == true
        and (wanted.npcReportVehicleTheft == true
            or wanted.npcReportAssault == true
            or wanted.npcReportShooting == true)

    local staticKey = table.concat({
        tostring(wanted.disablePoliceResponse == true),
        tostring(crimeReportsEnabled),
        tostring(wanted.disablePoliceScanner == true),
        tostring(wanted.disablePoliceHelicopters == true),
    }, '|')

    if staticKey ~= lastWantedStaticKey then
        if wanted.disablePoliceResponse then
            for i = 1, 15 do
                EnableDispatchService(i, false)
            end
            SetDispatchCopsForPlayer(PlayerId(), false)
            SetCreateRandomCops(false)
            SetCreateRandomCopsNotOnScenarios(false)
            SetCreateRandomCopsOnScenarios(false)
        else
            for i = 1, 15 do
                EnableDispatchService(i, true)
            end
            SetDispatchCopsForPlayer(PlayerId(), crimeReportsEnabled)
            SetCreateRandomCops(true)
            SetCreateRandomCopsNotOnScenarios(true)
            SetCreateRandomCopsOnScenarios(true)
        end

        if wanted.disablePoliceScanner then
            SetAudioFlag('PoliceScannerDisabled', true)
        else
            SetAudioFlag('PoliceScannerDisabled', false)
        end

        if wanted.disablePoliceHelicopters then
            EnableDispatchService(14, false)
        else
            EnableDispatchService(14, true)
        end

        lastWantedStaticKey = staticKey
    end

    SetPoliceIgnorePlayer(
        PlayerId(),
        wanted.disablePoliceChase == true
            or wanted.disablePoliceResponse == true
            or npcBehavior.ignorePlayer == true
    )

    if wanted.disableWantedLevel then
        SetMaxWantedLevel(0)
        SetPlayerWantedLevel(PlayerId(), 0, false)
        SetPlayerWantedLevelNow(PlayerId(), false)
    else
        SetMaxWantedLevel(wanted.maxWantedLevel)
    end
end

local function trimAmbientVehicles(cfg, vehicles, playerCoords, playerVehicle)
    local maxVehicles = (cfg.VehicleSettings and cfg.VehicleSettings.maxVehicles) or 100
    local multiplier = suppressionMultiplier((cfg.Advanced and cfg.Advanced.suppressionLevel) or 'medium')
    local densityApi = CBKAI.ClientDensity or {}
    local vehicleDensityFactor = type(densityApi.GetEffectiveVehicleDensityFactor) == 'function'
        and densityApi.GetEffectiveVehicleDensityFactor(cfg)
        or 1.0
    maxVehicles = math.max(0, math.floor(maxVehicles * multiplier))
    if math.max(0.0, math.min(1.0, vehicleDensityFactor)) <= 0.0 then
        maxVehicles = 0
    end
    local ambientVehicles = {}

    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if isAmbientVehicleEntity(vehicle) and vehicle ~= playerVehicle and not isProtectedPlayerVehicle(vehicle, cfg, playerCoords) then
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver == 0 or not IsPedAPlayer(driver) then
                ambientVehicles[#ambientVehicles + 1] = vehicle
            end
        end
    end

    if #ambientVehicles <= maxVehicles then
        return
    end

    table.sort(ambientVehicles, function(a, b)
        return #(GetEntityCoords(a) - playerCoords) > #(GetEntityCoords(b) - playerCoords)
    end)

    for i = maxVehicles + 1, #ambientVehicles do
        deleteVehicleSafely(ambientVehicles[i])
    end
end

local function applyStaticVehicleSuppression(settings)
    local suppressionKey = table.concat({
        tostring(settings.disablePoliceVehicles == true),
        tostring(settings.disableAmbulanceVehicles == true),
        tostring(settings.disableFiretruckVehicles == true),
        tostring(settings.disableBoats == true),
        tostring(settings.disableTrains == true),
    }, '|')

    if suppressionKey == lastVehicleSuppressionKey then
        return
    end

    if settings.disablePoliceVehicles then
        SetVehicleModelIsSuppressed(GetHashKey('police'), true)
        SetVehicleModelIsSuppressed(GetHashKey('police2'), true)
        SetVehicleModelIsSuppressed(GetHashKey('police3'), true)
        SetVehicleModelIsSuppressed(GetHashKey('police4'), true)
        SetVehicleModelIsSuppressed(GetHashKey('policeb'), true)
        SetVehicleModelIsSuppressed(GetHashKey('policet'), true)
    else
        SetVehicleModelIsSuppressed(GetHashKey('police'), false)
        SetVehicleModelIsSuppressed(GetHashKey('police2'), false)
        SetVehicleModelIsSuppressed(GetHashKey('police3'), false)
        SetVehicleModelIsSuppressed(GetHashKey('police4'), false)
        SetVehicleModelIsSuppressed(GetHashKey('policeb'), false)
        SetVehicleModelIsSuppressed(GetHashKey('policet'), false)
    end

    if settings.disableAmbulanceVehicles then
        SetVehicleModelIsSuppressed(GetHashKey('ambulance'), true)
    else
        SetVehicleModelIsSuppressed(GetHashKey('ambulance'), false)
    end

    if settings.disableFiretruckVehicles then
        SetVehicleModelIsSuppressed(GetHashKey('firetruk'), true)
    else
        SetVehicleModelIsSuppressed(GetHashKey('firetruk'), false)
    end

    if settings.disableBoats then
        SetRandomBoats(false)
    else
        SetRandomBoats(true)
    end

    if settings.disableTrains then
        SetRandomTrains(false)
    else
        SetRandomTrains(true)
    end

    lastVehicleSuppressionKey = suppressionKey
end

local function enforceVehicleSuppression(cfg, vehicles, playerCoords)
    local settings = cfg.VehicleSettings or {}
    local maxDistance = (cfg.Advanced and cfg.Advanced.maxNPCDistance) or 500.0

    updatePlayerVehicleTracking()
    applyStaticVehicleSuppression(settings)

    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if isAmbientVehicleEntity(vehicle) and #(GetEntityCoords(vehicle) - playerCoords) <= maxDistance then
            if isProtectedPlayerVehicle(vehicle, cfg, playerCoords) then
                goto continue_vehicle
            end

            local class = GetVehicleClass(vehicle)
            if (settings.disableBoats and class == 14)
                or (settings.disableHelicopters and class == 15)
                or (settings.disablePlanes and class == 16)
                or (settings.disablePoliceVehicles and class == 18)
            then
                deleteVehicleSafely(vehicle)
            else
                SetEntityCanBeDamaged(vehicle, settings.enableVehicleDamage ~= false)
                local driver = GetPedInVehicleSeat(vehicle, -1)
                if driver ~= 0 and not IsPedAPlayer(driver) then
                    if settings.vehiclesAvoidPlayer then
                        SetDriverAbility(driver, 1.0)
                        SetDriverAggressiveness(driver, 0.0)
                    elseif settings.vehiclesAvoidPlayer == false then
                        SetDriverAggressiveness(driver, 0.75)
                    end

                    if settings.vehiclesUseIndicators == false then
                        SetVehicleIndicatorLights(vehicle, 0, false)
                        SetVehicleIndicatorLights(vehicle, 1, false)
                    end

                    if cfg.NPCBehavior and cfg.NPCBehavior.disableAmbientHorns == true then
                        if setHornEnabledSafe(vehicle, false) then
                            globalHornMutedVehicles[vehicle] = true
                        end
                    elseif globalHornMutedVehicles[vehicle] then
                        setHornEnabledSafe(vehicle, true)
                        globalHornMutedVehicles[vehicle] = nil
                    end
                end
            end
        end

        ::continue_vehicle::
    end

    local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if settings.enableTraffic == false then
        trimAmbientVehicles({ VehicleSettings = { maxVehicles = 0 }, Advanced = cfg.Advanced }, vehicles, playerCoords, playerVehicle)
    elseif settings.maxVehicles then
        trimAmbientVehicles(cfg, vehicles, playerCoords, playerVehicle)
    end
end

local function resetStaticVehicleSuppression()
    SetVehicleModelIsSuppressed(GetHashKey('police'), false)
    SetVehicleModelIsSuppressed(GetHashKey('police2'), false)
    SetVehicleModelIsSuppressed(GetHashKey('police3'), false)
    SetVehicleModelIsSuppressed(GetHashKey('police4'), false)
    SetVehicleModelIsSuppressed(GetHashKey('policeb'), false)
    SetVehicleModelIsSuppressed(GetHashKey('policet'), false)
    SetVehicleModelIsSuppressed(GetHashKey('ambulance'), false)
    SetVehicleModelIsSuppressed(GetHashKey('firetruk'), false)
    SetRandomBoats(true)
    SetRandomTrains(true)
    lastVehicleSuppressionKey = nil
end

local function resetWantedSettings()
    for i = 1, 15 do
        EnableDispatchService(i, true)
    end

    SetDispatchCopsForPlayer(PlayerId(), true)
    SetCreateRandomCops(true)
    SetCreateRandomCopsNotOnScenarios(true)
    SetCreateRandomCopsOnScenarios(true)
    SetAudioFlag('PoliceScannerDisabled', false)
    EnableDispatchService(14, true)
    SetPoliceIgnorePlayer(PlayerId(), false)
    SetMaxWantedLevel(5)
    lastWantedStaticKey = nil
end

local function resetTrafficControllerState()
    for vehicle, _ in pairs(speedLimitedVehicles) do
        resetVehicleEmergencyState(vehicle)
    end

    for vehicle, _ in pairs(hornMutedVehicles) do
        resetVehicleEmergencyState(vehicle)
    end

    for vehicle, _ in pairs(globalHornMutedVehicles) do
        resetVehicleEmergencyState(vehicle)
    end

    for vehicle, driver in pairs(speechMutedDrivers) do
        if DoesEntityExist(driver) and CBKAI.ClientState.config.NPCBehavior.disableAmbientSpeech ~= true then
            StopPedSpeaking(driver, false)
        end
        speechMutedDrivers[vehicle] = nil
    end

    speedLimitedVehicles = {}
    hornMutedVehicles = {}
    speechMutedDrivers = {}
    globalHornMutedVehicles = {}
    bypassTaskUntil = {}
    bubbleStuckSince = {}
    bypassSideLock = {}
    bypassPlan = {}
end

local function isEmergencyVehicle(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local settings = CBKAI.ClientState.config.VehicleSettings.emergencyVehicleBehavior
    if not settings.enabled then
        return false
    end

    if GetVehicleClass(vehicle) == 18 then
        return true
    end

    local modelName = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    if settings.detectPolice and (string.find(modelName, 'polic') or string.find(modelName, 'sheriff') or string.find(modelName, 'fbi')) then
        return true
    end

    if settings.detectAmbulance and (string.find(modelName, 'ambulance') or string.find(modelName, 'ems')) then
        return true
    end

    if settings.detectFiretruck and string.find(modelName, 'fire') then
        return true
    end

    return false
end

local function emergencyDirection(targetVehicle, emergencyVehicle)
    local targetCoords = GetEntityCoords(targetVehicle)
    local emergencyCoords = GetEntityCoords(emergencyVehicle)

    local toEmergency = emergencyCoords - targetCoords
    local distance = #toEmergency
    if distance <= 0.001 then
        return 'side'
    end

    local forward = GetEntityForwardVector(targetVehicle)
    local aheadScore = ((forward.x * toEmergency.x) + (forward.y * toEmergency.y) + (forward.z * toEmergency.z)) / distance

    if aheadScore >= 0.1 then
        return 'front'
    end

    if aheadScore <= -0.1 then
        return 'behind'
    end

    return 'side'
end

RegisterNetEvent('cbk_ai:cl:trafficContext', function(payload)
    if type(payload) ~= 'table' or type(payload.pedestrianAnchors) ~= 'table' then
        return
    end

    CBKAI.ClientState.trafficContext = {
        pedestrianAnchors = payload.pedestrianAnchors,
        receivedAt = GetGameTimer(),
    }
end)

local function pointDirection(targetVehicle, pointCoords)
    local targetCoords = GetEntityCoords(targetVehicle)
    local toPoint = pointCoords - targetCoords
    local distance = #toPoint
    if distance <= 0.001 then
        return 'side'
    end

    local forward = GetEntityForwardVector(targetVehicle)
    local aheadScore = ((forward.x * toPoint.x) + (forward.y * toPoint.y) + (forward.z * toPoint.z)) / distance

    if aheadScore >= 0.1 then
        return 'front'
    end

    if aheadScore <= -0.1 then
        return 'behind'
    end

    return 'side'
end

local function isEmergencySirenActive(vehicle)
    if IsVehicleSirenOn(vehicle) then
        return true
    end

    local ok, audioOn = pcall(IsVehicleSirenAudioOn, vehicle)
    return ok and audioOn == true
end

local function isEmergencyActiveForResponse(vehicle, emergencyCfg)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    if not isEmergencyVehicle(vehicle) then
        return false
    end

    if emergencyCfg.requireSiren and not isEmergencySirenActive(vehicle) then
        -- Stopped emergency units should still create a safety bubble even if siren is muted.
        local stoppedThreshold = ((emergencyCfg.stoppedEmergencyMaxSpeedMph or 10.0) * 0.44704) + 0.25
        local isStoppedEmergency = emergencyCfg.stoppedEmergencyBubbleEnabled ~= false and GetEntitySpeed(vehicle) <= stoppedThreshold
        if not isStoppedEmergency then
            return false
        end

        -- Do not let the player's own current/recent emergency vehicle act as a
        -- stopped anchor when emergency signaling is off.
        local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if playerVehicle ~= 0 and vehicle == playerVehicle then
            return false
        end

        if lastPlayerVehicle ~= 0 and vehicle == lastPlayerVehicle then
            local retentionMs = ((CBKAI.ClientState.config or {}).VehicleSettings or {}).playerVehicleProtectionMs or 600000
            if (GetGameTimer() - (lastPlayerVehicleExitAt or 0)) <= retentionMs then
                return false
            end
        end
    end

    return true
end

local function isBypassPathClear(subjectVehicle, emergencyVehicle, pointA, pointB, clearanceRadius, vehicles)
    local corridorDir = pointB - pointA
    local corridorLen = #corridorDir
    if corridorLen <= 0.001 then
        return true
    end

    corridorDir = corridorDir / corridorLen
    -- Use the actual corridor direction (not NPC frame) for all directional checks so
    -- the stationaryBlock and headingOpposing tests fire correctly on angled bypass paths.
    local corridorLeft = vector3(-corridorDir.y, corridorDir.x, 0.0)

    for i = 1, #vehicles do
        local other = vehicles[i]
        if other ~= 0 and DoesEntityExist(other) and other ~= subjectVehicle and other ~= emergencyVehicle then
            local otherCoords = GetEntityCoords(other)
            local relA = otherCoords - pointA
            local longitudinal = (relA.x * corridorDir.x) + (relA.y * corridorDir.y) + (relA.z * corridorDir.z)
            if longitudinal >= -2.5 and longitudinal <= (corridorLen + 2.5) then
                local closest = pointA + (corridorDir * longitudinal)
                local lateralDist = #(otherCoords - closest)

                if lateralDist <= clearanceRadius then
                    -- Only treat traffic heading against the corridor as blocking.
                    local otherForward = GetEntityForwardVector(other)
                    local corridorDot = (otherForward.x * corridorDir.x) + (otherForward.y * corridorDir.y) + (otherForward.z * corridorDir.z)
                    local headingOpposing = corridorDot < -0.2

                    -- Block stationary objects that physically occupy the corridor ahead.
                    -- Use corridor-relative lateral (not NPC frame) for accurate sweep.
                    local toOther = otherCoords - pointA
                    local ahead = (toOther.x * corridorDir.x) + (toOther.y * corridorDir.y) + (toOther.z * corridorDir.z)
                    local toOtherLateral = math.abs((toOther.x * corridorLeft.x) + (toOther.y * corridorLeft.y) + (toOther.z * corridorLeft.z))
                    local stationaryBlock = GetEntitySpeed(other) < 1.0 and ahead > 0.0 and toOtherLateral <= clearanceRadius

                    if headingOpposing or stationaryBlock then
                        return false
                    end
                end
            end
        end
    end

    return true
end

local function trySafeOncomingBypass(driver, vehicle, emergencyVehicle, emergencyCfg, vehicles, forceCommit, lockedSideSign)
    if emergencyCfg.safeOncomingBypassEnabled ~= true then
        return false
    end

    local approachDir = emergencyDirection(vehicle, emergencyVehicle)
    if approachDir == 'behind' then
        return false
    end

    local now = GetGameTimer()

    local vehicleCoords = GetEntityCoords(vehicle)
    local emergencyCoords = GetEntityCoords(emergencyVehicle)
    local forward = GetEntityForwardVector(vehicle)
    local left = vector3(-forward.y, forward.x, 0.0)

    -- Suppress bypass when the blocking vehicle is perpendicular to traffic direction.
    -- A vehicle turned ~90° spans the full lane width — no viable bypass route exists.
    -- |dot| near 0 means perpendicular; |dot| near 1 means parallel (bypass appropriate).
    local emergencyForward = GetEntityForwardVector(emergencyVehicle)
    local alignmentDot = math.abs(
        (forward.x * emergencyForward.x) + (forward.y * emergencyForward.y) + (forward.z * emergencyForward.z)
    )
    if alignmentDot < (emergencyCfg.bypassMinAlignmentDot or 0.5) then
        -- Clear stale plan so it does not persist to next tick.
        bypassPlan[vehicle] = nil
        bypassSideLock[vehicle] = nil
        return false
    end

    local lookAhead = emergencyCfg.safeBypassLookAhead or 11.8
    local lateralOffset = emergencyCfg.safeBypassLateralOffset or 5.4
    local relEmergency = emergencyCoords - vehicleCoords
    local emergencyLateralDot = (relEmergency.x * left.x) + (relEmergency.y * left.y) + (relEmergency.z * left.z)
    local forceAwayDeadzone = 1.25
    local emergencyCentered = math.abs(emergencyLateralDot) < forceAwayDeadzone
    local forceAwayFromEmergency = true
    -- Prefer bypassing on the side opposite the stopped emergency position.
    -- When emergency is near centerline from the NPC perspective, default to left-lane pass (+1)
    -- to avoid indecisive steering back toward the blocker.
    local preferredSign = emergencyCentered and 1.0 or (emergencyLateralDot >= 0.0 and -1.0 or 1.0)
    local fallbackSign = -preferredSign
    local clearanceRadius = emergencyCfg.safeBypassClearanceRadius or 6.4
    -- Engagement distance is intentionally independent from lookAhead so increasing
    -- lookAhead only affects path shape, not how early vehicles begin bypass logic.
    local commitDistance = math.max(
        (emergencyCfg.stoppedEmergencyBubbleRadius or 20.0) * 1.75,
        (emergencyCfg.slowPassRadius or 80.0) * 0.75
    )

    local existingPlan = bypassPlan[vehicle]
    if existingPlan
        and existingPlan.anchorVehicle == emergencyVehicle
        and now <= (existingPlan.expiresAt or 0)
    then
        if forceAwayFromEmergency then
            local sideSign = existingPlan.sideSign or preferredSign
            local emergencyOnLeft = emergencyLateralDot >= 0.0
            local towardEmergency = (emergencyOnLeft and sideSign == 1.0) or ((not emergencyOnLeft) and sideSign == -1.0)
            if towardEmergency then
                bypassPlan[vehicle] = nil
                bypassSideLock[vehicle] = nil
                existingPlan = nil
            end
        end

    end

    if existingPlan
        and existingPlan.anchorVehicle == emergencyVehicle
        and now <= (existingPlan.expiresAt or 0)
    then
        local styleToUse = existingPlan.styleToUse or (emergencyCfg.safeBypassDrivingStyle or 786603)
        local bypassSpeedMps = existingPlan.speedMps or ((emergencyCfg.safeBypassSpeedMph or 18.0) * 0.44704)
        SetDriveTaskDrivingStyle(driver, styleToUse)

        if existingPlan.phase == 1 and existingPlan.laneEntryPoint then
            local relToEmergency = vehicleCoords - emergencyCoords
            local lateralFromEmergency = math.abs((relToEmergency.x * left.x) + (relToEmergency.y * left.y) + (relToEmergency.z * left.z))
            local targetLateral = existingPlan.lateralOffset or lateralOffset
            if lateralFromEmergency >= (targetLateral * 0.75) or now >= (existingPlan.phase1Until or 0) then
                existingPlan.phase = 2
            end
        end

        if existingPlan.phase == 1 and existingPlan.laneEntryPoint then
            local p = existingPlan.laneEntryPoint
            TaskVehicleDriveToCoordLongrange(driver, vehicle, p.x, p.y, p.z, bypassSpeedMps, styleToUse, 2.0)
            bypassTaskUntil[vehicle] = now + 900
            return true, existingPlan.sideSign
        end

        if existingPlan.targetPoint then
            local p = existingPlan.targetPoint
            TaskVehicleDriveToCoordLongrange(driver, vehicle, p.x, p.y, p.z, bypassSpeedMps, styleToUse, 10.0)
            bypassTaskUntil[vehicle] = now + 1200
            return true, existingPlan.sideSign
        end
    end

    if now < (bypassTaskUntil[vehicle] or 0) then
        return true, lockedSideSign
    end

    if #(vehicleCoords - emergencyCoords) > commitDistance then
        return false
    end

    local targetPoint = nil
    local selectedSide = nil
    local selectedSideSign = nil
    local effectiveLateral = lateralOffset
    local sideOrder = emergencyCentered and { preferredSign } or { preferredSign, fallbackSign }
    if lockedSideSign == 1 or lockedSideSign == -1 then
        sideOrder = { lockedSideSign, -lockedSideSign }
    end

    for _, sideSign in ipairs(sideOrder) do
        if forceAwayFromEmergency then
            local emergencyOnLeft = emergencyLateralDot >= 0.0
            local towardEmergency = (emergencyOnLeft and sideSign == 1.0) or ((not emergencyOnLeft) and sideSign == -1.0)
            if towardEmergency then
                goto continue_side
            end
        end

        effectiveLateral = lateralOffset
        local side = left * (effectiveLateral * sideSign)
        local midpoint = vehicleCoords + (forward * (lookAhead * 0.4)) + side
        -- Target is placed 2x lookAhead past the emergency so the driving task stays live
        -- long enough for the NPC to actually clear the vehicle before GTA native steering resumes.
        local candidateTarget = emergencyCoords + (forward * (lookAhead * 2.0)) + side
        local prePoint = vehicleCoords + (forward * (lookAhead * 0.2)) + (side * 0.6)

        if forceCommit
            or (
                isBypassPathClear(vehicle, emergencyVehicle, prePoint, midpoint, clearanceRadius, vehicles)
                and isBypassPathClear(vehicle, emergencyVehicle, midpoint, candidateTarget, clearanceRadius, vehicles)
            )
        then
            targetPoint = candidateTarget
            selectedSide = side
            selectedSideSign = sideSign
            break
        end

        ::continue_side::
    end

    if not targetPoint then
        return false, nil
    end

    local bypassSpeedMps = (emergencyCfg.safeBypassSpeedMph or 18.0) * 0.44704
    local drivingStyle = emergencyCfg.safeBypassDrivingStyle or 786603
    local forceDrivingStyle = emergencyCfg.safeBypassForceDrivingStyle or 1074528293
    local styleToUse = forceCommit and forceDrivingStyle or drivingStyle

    local laneEntryPoint = vehicleCoords + (forward * (lookAhead * 0.85)) + selectedSide
    local relToEmergency = vehicleCoords - emergencyCoords
    local lateralFromEmergency = math.abs((relToEmergency.x * left.x) + (relToEmergency.y * left.y) + (relToEmergency.z * left.z))
    local laneEntryNeeded = lateralFromEmergency < (effectiveLateral * 0.65)

    SetDriveTaskDrivingStyle(driver, styleToUse)
    if forceCommit and laneEntryNeeded then
        -- Phase 1: commit laterally into pass lane first.
        TaskVehicleDriveToCoordLongrange(driver, vehicle, laneEntryPoint.x, laneEntryPoint.y, laneEntryPoint.z, bypassSpeedMps, styleToUse, 2.0)
        bypassTaskUntil[vehicle] = now + 1200
        bypassPlan[vehicle] = {
            anchorVehicle = emergencyVehicle,
            sideSign = selectedSideSign,
            lateralOffset = effectiveLateral,
            laneEntryPoint = laneEntryPoint,
            targetPoint = targetPoint,
            phase = 1,
            phase1Until = now + 1200,
            speedMps = bypassSpeedMps,
            styleToUse = styleToUse,
            expiresAt = now + 6500,
        }
        SetDriverAbility(driver, 1.0)
        SetDriverAggressiveness(driver, 0.35)
        return true, selectedSideSign
    end

    -- Phase 2: overtake and clear emergency anchor.
    TaskVehicleDriveToCoordLongrange(driver, vehicle, targetPoint.x, targetPoint.y, targetPoint.z, bypassSpeedMps, styleToUse, 10.0)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, forceCommit and 0.35 or 0.25)

    local holdMs = emergencyCfg.safeBypassTaskMs or 5000
    bypassTaskUntil[vehicle] = now + holdMs
    bypassPlan[vehicle] = {
        anchorVehicle = emergencyVehicle,
        sideSign = selectedSideSign,
        lateralOffset = effectiveLateral,
        targetPoint = targetPoint,
        phase = 2,
        speedMps = bypassSpeedMps,
        styleToUse = styleToUse,
        expiresAt = now + holdMs,
    }
    return true, selectedSideSign
end

local function hasQueueLeadVehicle(subjectVehicle, emergencyVehicle, vehicles, emergencyCfg)
    if subjectVehicle == 0 or emergencyVehicle == 0 then
        return false
    end

    if not DoesEntityExist(subjectVehicle) or not DoesEntityExist(emergencyVehicle) then
        return false
    end

    local subjectCoords = GetEntityCoords(subjectVehicle)
    local emergencyCoords = GetEntityCoords(emergencyVehicle)
    local forward = GetEntityForwardVector(subjectVehicle)
    local left = vector3(-forward.y, forward.x, 0.0)

    local toEmergency = emergencyCoords - subjectCoords
    local emergencyLongitudinal = (toEmergency.x * forward.x) + (toEmergency.y * forward.y) + (toEmergency.z * forward.z)
    if emergencyLongitudinal <= 4.0 then
        return false
    end

    local laneHalfWidth = math.max(2.8, (emergencyCfg.safeBypassClearanceRadius or 6.4) * 0.7)
    for i = 1, #vehicles do
        local other = vehicles[i]
        if other ~= 0 and other ~= subjectVehicle and other ~= emergencyVehicle and DoesEntityExist(other) then
            local otherDriver = GetPedInVehicleSeat(other, -1)
            if otherDriver ~= 0 and not IsPedAPlayer(otherDriver) then
                local rel = GetEntityCoords(other) - subjectCoords
                local longitudinal = (rel.x * forward.x) + (rel.y * forward.y) + (rel.z * forward.z)
                if longitudinal > 3.0 and longitudinal < (emergencyLongitudinal - 2.0) then
                    local lateral = math.abs((rel.x * left.x) + (rel.y * left.y) + (rel.z * left.z))
                    if lateral <= laneHalfWidth then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function trySafePedestrianBypass(driver, vehicle, pedestrianCoords, emergencyCfg, vehicles)
    if not pedestrianCoords then
        return false
    end

    local now = GetGameTimer()
    if now < (bypassTaskUntil[vehicle] or 0) then
        return true
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local left = vector3(-forward.y, forward.x, 0.0)
    local rel = pedestrianCoords - vehicleCoords
    local lateralDot = (rel.x * left.x) + (rel.y * left.y) + (rel.z * left.z)
    local offsetSign = lateralDot >= 0.0 and -1.0 or 1.0

    local lookAhead = emergencyCfg.safeBypassLookAhead or 11.8
    local lateralOffset = emergencyCfg.safeBypassLateralOffset or 5.4
    local lateral = left * (lateralOffset * offsetSign)
    local midpoint = vehicleCoords + (forward * (lookAhead * 0.45)) + (lateral * 0.8)
    local targetPoint = pedestrianCoords + (forward * lookAhead) + lateral
    local clearanceRadius = emergencyCfg.safeBypassClearanceRadius or 6.4

    if #(vehicleCoords - pedestrianCoords) > (lookAhead * 3.0) then
        return false
    end

    local prePoint = vehicleCoords + (forward * (lookAhead * 0.2)) + (lateral * 0.5)
    if not isBypassPathClear(vehicle, 0, prePoint, midpoint, clearanceRadius, vehicles)
        or not isBypassPathClear(vehicle, 0, midpoint, targetPoint, clearanceRadius, vehicles)
    then
        return false
    end

    local bypassSpeedMps = math.min(emergencyCfg.safeBypassSpeedMph or 10.0, emergencyCfg.slowPassSpeed or 10.0) * 0.44704
    local drivingStyle = emergencyCfg.safeBypassDrivingStyle or 786603
    TaskVehicleDriveToCoordLongrange(driver, vehicle, targetPoint.x, targetPoint.y, targetPoint.z, bypassSpeedMps, drivingStyle, 5.0)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.0)

    bypassTaskUntil[vehicle] = now + (emergencyCfg.safeBypassTaskMs or 5000)
    return true
end

local function collectEmergencyAnchors(emergencyCfg, vehicles, playerCoords)
    local stoppedAnchors = {}
    local maxStoppedAnchors = emergencyCfg.maxStoppedEmergencyAnchors or 6
    local stoppedSearchRadius = emergencyCfg.stoppedEmergencyBubbleSearchRadius or 500.0
    local stoppedThresholdMps = (emergencyCfg.stoppedEmergencyMaxSpeedMph or 2.0) * 0.44704

    for i = 1, #vehicles do
        if #stoppedAnchors >= maxStoppedAnchors then
            break
        end

        local vehicle = vehicles[i]
        if vehicle ~= 0 and DoesEntityExist(vehicle) and isEmergencyActiveForResponse(vehicle, emergencyCfg) then
            local coords = GetEntityCoords(vehicle)
            local distanceToPlayer = #(coords - playerCoords)
            local speed = GetEntitySpeed(vehicle)

            if speed <= stoppedThresholdMps and #stoppedAnchors < maxStoppedAnchors and distanceToPlayer <= stoppedSearchRadius then
                stoppedAnchors[#stoppedAnchors + 1] = {
                    vehicle = vehicle,
                    coords = coords,
                }
            end
        end
    end

    return stoppedAnchors
end

local function collectPlayerAvoidanceAnchors(searchRadius)
    local anchors = {}
    local context = CBKAI.ClientState.trafficContext
    if type(context) ~= 'table' or type(context.pedestrianAnchors) ~= 'table' then
        return anchors
    end

    if (GetGameTimer() - (context.receivedAt or 0)) > 2500 then
        return anchors
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    for i = 1, #context.pedestrianAnchors do
        local anchor = context.pedestrianAnchors[i]
        local x = tonumber(anchor.x)
        local y = tonumber(anchor.y)
        local z = tonumber(anchor.z)
        if x and y and z then
            local coords = vector3(x + 0.0, y + 0.0, z + 0.0)
            if #(coords - playerCoords) <= searchRadius then
                anchors[#anchors + 1] = {
                    coords = coords,
                }
            end
        end
    end

    return anchors
end

local function getNearestEmergencyAnchor(vehicle, anchors)
    if #anchors == 0 then
        return 0, math.huge
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local nearestVehicle = 0
    local nearestDistance = math.huge

    for i = 1, #anchors do
        local anchor = anchors[i]
        local dist = #(vehicleCoords - anchor.coords)
        if dist < nearestDistance then
            nearestVehicle = anchor.vehicle
            nearestDistance = dist
        end
    end

    return nearestVehicle, nearestDistance
end

local function getNearestPlayerAnchor(vehicle, anchors)
    if #anchors == 0 then
        return nil, math.huge
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local nearestCoords = nil
    local nearestDistance = math.huge

    for i = 1, #anchors do
        local anchor = anchors[i]
        local dist = #(vehicleCoords - anchor.coords)
        if dist < nearestDistance then
            nearestCoords = anchor.coords
            nearestDistance = dist
        end
    end

    return nearestCoords, nearestDistance
end

local function shouldRespondToStoppedEmergency(subjectVehicle, emergencyVehicle, emergencyCfg)
    if subjectVehicle == 0 or emergencyVehicle == 0 then
        return false
    end

    if not DoesEntityExist(subjectVehicle) or not DoesEntityExist(emergencyVehicle) then
        return false
    end

    local subjectCoords = GetEntityCoords(subjectVehicle)
    local emergencyCoords = GetEntityCoords(emergencyVehicle)
    local subjectForward = GetEntityForwardVector(subjectVehicle)
    local emergencyForward = GetEntityForwardVector(emergencyVehicle)
    local directionDot = (subjectForward.x * emergencyForward.x)
        + (subjectForward.y * emergencyForward.y)
        + (subjectForward.z * emergencyForward.z)

    local minSameDirectionDot = emergencyCfg.sameDirectionDotMin or 0.25
    if directionDot < minSameDirectionDot then
        local emergencyStoppedThreshold = ((emergencyCfg.stoppedEmergencyMaxSpeedMph or 10.0) * 0.44704) + 0.25
        local emergencySpeed = GetEntitySpeed(emergencyVehicle)
        -- Allow angled stopped emergency vehicles, but reject clearly opposite-direction flow.
        if emergencySpeed > emergencyStoppedThreshold or directionDot < -0.25 then
            return false
        end
    end

    local subjectToEmergency = emergencyCoords - subjectCoords
    local aheadScore = (subjectForward.x * subjectToEmergency.x)
        + (subjectForward.y * subjectToEmergency.y)
        + (subjectForward.z * subjectToEmergency.z)

    local minBehindDistance = emergencyCfg.minBehindDistanceForResponse or 3.0
    if aheadScore < minBehindDistance then
        return false
    end

    return true
end

CreateThread(function()
    while true do
        local cfg = CBKAI.ClientState.config
        local vehSettings = cfg.VehicleSettings
        local playerCoords = GetEntityCoords(PlayerPedId())
        local vehiclePool = GetGamePool('CVehicle') or {}
        local now = GetGameTimer()
        local suppressionSweepInterval = math.max(750, math.min(2000, (cfg.Advanced and cfg.Advanced.updateInterval) or 1000))
        local enableNPCs = cfg.EnableNPCs ~= false

        if lastEnableNPCsState == nil or lastEnableNPCsState ~= enableNPCs then
            lastEnableNPCsState = enableNPCs
            lastSuppressionSweepAt = 0
            if enableNPCs then
                masterDisableStateApplied = false
            end
        end

        if not enableNPCs then
            if not masterDisableStateApplied then
                resetTrafficControllerState()
                resetStaticVehicleSuppression()
                resetWantedSettings()
                masterDisableStateApplied = true
            end
        else
            masterDisableStateApplied = false
            if (now - lastSuppressionSweepAt) >= suppressionSweepInterval then
                enforceVehicleSuppression(cfg, vehiclePool, playerCoords)
                lastSuppressionSweepAt = now
            else
                updatePlayerVehicleTracking()
                applyStaticVehicleSuppression(vehSettings)
            end

            applyWantedSettings(cfg)

            local emergencyCfg = vehSettings.emergencyVehicleBehavior
            if emergencyCfg.enabled then
            local anchors = {}
            if emergencyCfg.stoppedEmergencyBubbleEnabled ~= false then
                anchors = collectEmergencyAnchors(emergencyCfg, vehiclePool, playerCoords)
            end

            local playerAnchors = {}
            if vehSettings.vehiclesAvoidPlayer ~= false then
                playerAnchors = collectPlayerAvoidanceAnchors(math.max(emergencyCfg.courtesyRadius or 100.0, 100.0))
            end

            local bubbleRadius = emergencyCfg.stoppedEmergencyBubbleRadius or math.max((emergencyCfg.slowPassRadius or 80.0) * 2.2, 120.0)
            local hardStopRadius = emergencyCfg.stoppedEmergencyHardStopRadius or 12.0
            local hardStopMs = emergencyCfg.stoppedEmergencyHardStopActionMs or 1200
            local slowPassRadius = emergencyCfg.slowPassRadius or 80.0
            local approachRadius = math.max(slowPassRadius * 2.6, slowPassRadius + 45.0)
            local bypassAttemptRadius = math.max(bubbleRadius, slowPassRadius * 0.8)
            local slowPassSpeed = (emergencyCfg.slowPassSpeed or 10.0) * 0.44704
            local approachSpeed = math.max(slowPassSpeed + 1.5, 20.0 * 0.44704)
            local pedestrianResponseRadius = math.max(12.0, (emergencyCfg.stoppedEmergencyBubbleRadius or 20.0) * 0.75)
            local pedestrianHardStopRadius = math.max(5.0, (emergencyCfg.stoppedEmergencyHardStopRadius or 12.0) * 0.5)
            local pedestrianSlowSpeed = math.max(4.0, math.min(emergencyCfg.slowPassSpeed or 10.0, 8.0)) * 0.44704

            local nearbyVehicles = vehiclePool
            for i = 1, #nearbyVehicles do
                local vehicle = nearbyVehicles[i]
                if vehicle == 0 or not DoesEntityExist(vehicle) then
                    resetVehicleEmergencyState(vehicle)
                    goto continue_vehicle
                end
                if not isAmbientVehicleEntity(vehicle) then
                    resetVehicleEmergencyState(vehicle)
                    goto continue_vehicle
                end

                local driver = GetPedInVehicleSeat(vehicle, -1)
                if driver == 0 or IsPedAPlayer(driver) then
                    resetVehicleEmergencyState(vehicle)
                    goto continue_vehicle
                end

                local anchorVehicle, distance = getNearestEmergencyAnchor(vehicle, anchors)
                local inBubble = anchorVehicle ~= 0 and distance <= bubbleRadius
                if not inBubble then
                    bypassSideLock[vehicle] = nil
                    bypassPlan[vehicle] = nil
                end
                local approachDirection = 'side'
                local validBubbleTarget = false
                if inBubble then
                    approachDirection = emergencyDirection(vehicle, anchorVehicle)
                    validBubbleTarget = shouldRespondToStoppedEmergency(vehicle, anchorVehicle, emergencyCfg)
                end
                local isApproaching = inBubble and validBubbleTarget and approachDirection == 'front'

                if isApproaching and emergencyCfg.slowPassEnabled then
                    local bypassApplied = false
                    local currentSpeed = GetEntitySpeed(vehicle)
                    local queueBlocked = hasQueueLeadVehicle(vehicle, anchorVehicle, vehiclePool, emergencyCfg)
                    if currentSpeed <= 0.8 then
                        bubbleStuckSince[vehicle] = bubbleStuckSince[vehicle] or now
                    else
                        bubbleStuckSince[vehicle] = nil
                    end
                    local stuckMs = bubbleStuckSince[vehicle] and (now - bubbleStuckSince[vehicle]) or 0
                    local forceCommit = stuckMs >= 1200
                    if queueBlocked then
                        bypassPlan[vehicle] = nil
                        bypassSideLock[vehicle] = nil
                    elseif distance <= bypassAttemptRadius then
                        local selectedSideSign = nil
                        bypassApplied, selectedSideSign = trySafeOncomingBypass(
                            driver,
                            vehicle,
                            anchorVehicle,
                            emergencyCfg,
                            vehiclePool,
                            forceCommit,
                            bypassSideLock[vehicle]
                        )
                        if selectedSideSign then
                            bypassSideLock[vehicle] = selectedSideSign
                        end
                    end

                    if bypassApplied then
                        if speedLimitedVehicles[vehicle] then
                            SetVehicleMaxSpeed(vehicle, 0.0)
                            speedLimitedVehicles[vehicle] = nil
                        end
                    else
                        local targetSpeed = slowPassSpeed
                        if distance > slowPassRadius then
                            local t = clamp((distance - slowPassRadius) / (approachRadius - slowPassRadius), 0.0, 1.0)
                            targetSpeed = slowPassSpeed + ((approachSpeed - slowPassSpeed) * t)
                        end

                        local distanceFactor = clamp((approachRadius - distance) / approachRadius, 0.0, 1.0)
                        local smoothStep = 1.4 + (2.0 * distanceFactor)
                        local limitedSpeed = targetSpeed
                        if currentSpeed > targetSpeed then
                            limitedSpeed = math.max(targetSpeed, currentSpeed - smoothStep)
                        end

                        SetVehicleMaxSpeed(vehicle, limitedSpeed)
                        speedLimitedVehicles[vehicle] = true
                        SetDriverAbility(driver, 1.0)
                        SetDriverAggressiveness(driver, 0.0)

                        if hardStopMs > 0 and hardStopRadius > 0.0 and distance <= hardStopRadius then
                            TaskVehicleTempAction(driver, vehicle, 27, hardStopMs)
                        end
                    end
                elseif inBubble and emergencyCfg.slowPassEnabled then
                    bubbleStuckSince[vehicle] = nil
                    -- Vehicle is inside the bubble but approaching from the side or opposite direction.
                    -- Still enforce slow-pass speed so the bubble is respected in all lanes.
                    SetVehicleMaxSpeed(vehicle, slowPassSpeed)
                    speedLimitedVehicles[vehicle] = true
                    SetDriverAbility(driver, 1.0)
                    SetDriverAggressiveness(driver, 0.0)
                elseif speedLimitedVehicles[vehicle] then
                    bubbleStuckSince[vehicle] = nil
                    bypassSideLock[vehicle] = nil
                    bypassPlan[vehicle] = nil
                    SetVehicleMaxSpeed(vehicle, 0.0)
                    speedLimitedVehicles[vehicle] = nil
                end

                if (not isApproaching) and bypassTaskUntil[vehicle] then
                    if GetGameTimer() >= bypassTaskUntil[vehicle] then
                        bypassTaskUntil[vehicle] = nil
                    end
                end

                if isApproaching and emergencyCfg.disableSpeechNearEmergency and distance <= (emergencyCfg.courtesyRadius or bubbleRadius) then
                    StopPedSpeaking(driver, true)
                    speechMutedDrivers[vehicle] = driver
                elseif speechMutedDrivers[vehicle] then
                    if DoesEntityExist(speechMutedDrivers[vehicle]) then
                        if CBKAI.ClientState.config.NPCBehavior.disableAmbientSpeech ~= true then
                            StopPedSpeaking(speechMutedDrivers[vehicle], false)
                        end
                    end
                    speechMutedDrivers[vehicle] = nil
                end

                if isApproaching and emergencyCfg.disableHornNearEmergency and distance <= (emergencyCfg.courtesyRadius or bubbleRadius) then
                    if setHornEnabledSafe(vehicle, false) then
                        hornMutedVehicles[vehicle] = true
                    else
                        SetDriverAbility(driver, 1.0)
                        SetDriverAggressiveness(driver, 0.0)
                    end
                elseif hornMutedVehicles[vehicle] then
                    if not globalHornMutedVehicles[vehicle] then
                        setHornEnabledSafe(vehicle, true)
                    end
                    hornMutedVehicles[vehicle] = nil
                end

                if vehSettings.vehiclesAvoidPlayer ~= false and not isApproaching then
                    local avoidCoords, avoidDistance = getNearestPlayerAnchor(vehicle, playerAnchors)
                    if avoidCoords and avoidDistance <= pedestrianResponseRadius then
                        local direction = pointDirection(vehicle, avoidCoords)
                        if direction ~= 'behind' then
                            local bypassApplied = trySafePedestrianBypass(driver, vehicle, avoidCoords, emergencyCfg, vehiclePool)
                            if bypassApplied then
                                if speedLimitedVehicles[vehicle] then
                                    SetVehicleMaxSpeed(vehicle, 0.0)
                                    speedLimitedVehicles[vehicle] = nil
                                end
                            else
                                SetVehicleMaxSpeed(vehicle, pedestrianSlowSpeed)
                                speedLimitedVehicles[vehicle] = true
                                SetDriverAbility(driver, 1.0)
                                SetDriverAggressiveness(driver, 0.0)

                                if avoidDistance <= pedestrianHardStopRadius then
                                    TaskVehicleTempAction(driver, vehicle, 27, math.max(500, hardStopMs))
                                end
                            end
                        end
                    end
                end

                ::continue_vehicle::
            end
        end
        end

        local updateInterval = (cfg.Advanced and cfg.Advanced.updateInterval) or 1000
        Wait(math.max(100, math.min(250, updateInterval)))
    end
end)

AddEventHandler('cbk_ai:localWorldCleared', function()
    speedLimitedVehicles = {}
    hornMutedVehicles = {}
    speechMutedDrivers = {}
    globalHornMutedVehicles = {}
    bypassTaskUntil = {}
    bubbleStuckSince = {}
    bypassSideLock = {}
    bypassPlan = {}
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    resetTrafficControllerState()
    resetStaticVehicleSuppression()
    resetWantedSettings()
    masterDisableStateApplied = false
    lastEnableNPCsState = nil
    lastSuppressionSweepAt = 0
end)
