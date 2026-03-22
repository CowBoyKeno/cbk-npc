CBKAI = CBKAI or {}

CBKAI.ClientState = CBKAI.ClientState or {
    config = Config,
    revision = 0,
}

CBKAI.RuntimeState = CBKAI.RuntimeState or {
    lastVehicle = 0,
    seenNearbyPeds = {},
    lastReportAt = 0,
    lastCleanupAt = 0,
    lastPedTrimAt = 0,
    lastDebugAt = 0,
    currentPlayerVehicleHandle = 0,
    currentPlayerVehicleNetId = 0,
    lastPlayerVehicleHandle = 0,
    lastPlayerVehicleNetId = 0,
    lastPlayerVehicleExitAt = 0,
    deadPedSeenAt = {},
    wreckedVehicleSeenAt = {},
    abandonedVehicleSeenAt = {},
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function deepClone(value)
    if type(value) ~= 'table' then
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        out[k] = deepClone(v)
    end
    return out
end

local animalModelGroups = {
    animals = {
        'a_c_boar', 'a_c_cat_01', 'a_c_chickenhawk', 'a_c_chimp', 'a_c_chop', 'a_c_cormorant',
        'a_c_cow', 'a_c_coyote', 'a_c_crow', 'a_c_deer', 'a_c_fish', 'a_c_hen', 'a_c_humpback',
        'a_c_killerwhale', 'a_c_mtlion', 'a_c_panther', 'a_c_pig', 'a_c_pigeon', 'a_c_poodle',
        'a_c_pug', 'a_c_rabbit_01', 'a_c_rat', 'a_c_retriever', 'a_c_rhesus', 'a_c_rottweiler',
        'a_c_seagull', 'a_c_sharkhammer', 'a_c_sharktiger', 'a_c_shepherd', 'a_c_stingray',
        'a_c_westy',
    },
    birds = {
        'a_c_chickenhawk', 'a_c_cormorant', 'a_c_crow', 'a_c_pigeon', 'a_c_seagull',
    },
    fish = {
        'a_c_fish', 'a_c_stingray', 'a_c_sharkhammer', 'a_c_sharktiger', 'a_c_humpback', 'a_c_killerwhale',
    },
    seagulls = {
        'a_c_seagull',
    },
}

local relationshipGroups = {
    'PLAYER',
    'COP',
    'CIVMALE',
    'CIVFEMALE',
    'GANG_1',
    'GANG_2',
    'GANG_9',
    'GANG_10',
    'AMBIENT_GANG_LOST',
    'AMBIENT_GANG_MEXICAN',
    'AMBIENT_GANG_FAMILY',
    'AMBIENT_GANG_BALLAS',
}

local function normalizeModelHash(model)
    if type(model) == 'number' then
        return model
    end

    if type(model) == 'string' and model ~= '' then
        return GetHashKey(model)
    end

    return nil
end

local function buildModelLookup(models)
    local lookup = {}
    for i = 1, #models do
        local modelHash = normalizeModelHash(models[i])
        if modelHash then
            lookup[modelHash] = true
        end
    end
    return lookup
end

local animalModelLookups = {
    animals = buildModelLookup(animalModelGroups.animals),
    birds = buildModelLookup(animalModelGroups.birds),
    fish = buildModelLookup(animalModelGroups.fish),
    seagulls = buildModelLookup(animalModelGroups.seagulls),
}

local function isModelInLookup(modelHash, models)
    return models[modelHash] == true
end

local function isAnimalModel(modelHash, config)
    local scenario = config.ScenarioSettings or {}
    if not scenario.disableAnimals and not scenario.disableBirds and not scenario.disableFish and not scenario.disableSeagulls then
        return false
    end

    if scenario.disableAnimals and isModelInLookup(modelHash, animalModelLookups.animals) then
        return true
    end

    if scenario.disableBirds and isModelInLookup(modelHash, animalModelLookups.birds) then
        return true
    end

    if scenario.disableFish and isModelInLookup(modelHash, animalModelLookups.fish) then
        return true
    end

    if scenario.disableSeagulls and isModelInLookup(modelHash, animalModelLookups.seagulls) then
        return true
    end

    return false
end

local function getPedModelRules(config)
    local blacklist = config.Blacklist or {}
    local whitelist = config.Whitelist or {}

    return {
        blacklistEnabled = blacklist.enabled == true,
        blacklistModels = buildModelLookup(blacklist.models or {}),
        whitelistEnabled = whitelist.enabled == true,
        whitelistModels = buildModelLookup(whitelist.models or {}),
    }
end

local function isPedModelAllowed(modelHash, rules)
    if rules.blacklistEnabled and isModelInLookup(modelHash, rules.blacklistModels) then
        return false
    end

    if rules.whitelistEnabled and not isModelInLookup(modelHash, rules.whitelistModels) then
        return false
    end

    return true
end

local function deleteEntitySafely(entity)
    if entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local timeout = GetGameTimer() + 250
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end

    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
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

local function isVehicleOccupiedByAnyPed(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxPassengers - 1 do
        if GetPedInVehicleSeat(vehicle, seat) ~= 0 then
            return true
        end
    end

    return false
end

local function applyRelationshipSettings(config)
    local settings = config.Relationships
    if not settings or settings.enabled == false then
        return
    end

    local playerGroup = GetHashKey('PLAYER')
    local copGroup = GetHashKey('COP')
    local gangGroups = {
        GetHashKey('GANG_1'),
        GetHashKey('GANG_2'),
        GetHashKey('GANG_9'),
        GetHashKey('GANG_10'),
        GetHashKey('AMBIENT_GANG_LOST'),
        GetHashKey('AMBIENT_GANG_MEXICAN'),
        GetHashKey('AMBIENT_GANG_FAMILY'),
        GetHashKey('AMBIENT_GANG_BALLAS'),
    }

    for i = 1, #relationshipGroups do
        local groupHash = GetHashKey(relationshipGroups[i])
        SetRelationshipBetweenGroups(settings.playerToNPC or 3, playerGroup, groupHash)
        SetRelationshipBetweenGroups(settings.npcToPlayer or 3, groupHash, playerGroup)
    end

    SetRelationshipBetweenGroups(settings.copsToPlayer or 0, copGroup, playerGroup)

    local npcToNpc = settings.npcToNPC or 3
    for i = 1, #relationshipGroups do
        local groupA = GetHashKey(relationshipGroups[i])
        for j = 1, #relationshipGroups do
            local groupB = GetHashKey(relationshipGroups[j])
            SetRelationshipBetweenGroups(npcToNpc, groupA, groupB)
        end
    end

    for i = 1, #gangGroups do
        SetRelationshipBetweenGroups(settings.copsToGangs or 5, copGroup, gangGroups[i])
        SetRelationshipBetweenGroups(settings.copsToGangs or 5, gangGroups[i], copGroup)
        SetRelationshipBetweenGroups(settings.gangsToPlayer or 4, gangGroups[i], playerGroup)
    end
end

local function emitRuntimeEvents(config, playerPed, playerCoords)
    if not config.Events or config.Events.enabled == false then
        return
    end

    local runtime = CBKAI.RuntimeState
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if config.Events.onPlayerEnterVehicle and vehicle ~= 0 and runtime.lastVehicle == 0 then
        TriggerEvent('cbk_ai:onPlayerEnterVehicle', vehicle)
    elseif config.Events.onPlayerExitVehicle and vehicle == 0 and runtime.lastVehicle ~= 0 then
        TriggerEvent('cbk_ai:onPlayerExitVehicle', runtime.lastVehicle)
    end
    runtime.lastVehicle = vehicle

    if not config.Events.onNPCSpawn then
        return
    end

    local now = GetGameTimer()
    local seenThisTick = {}
    local nearbyPeds = GetGamePool('CPed') or {}
    for i = 1, #nearbyPeds do
        local ped = nearbyPeds[i]
        if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local distance = #(GetEntityCoords(ped) - playerCoords)
            if distance <= 80.0 then
                seenThisTick[ped] = true
                if not runtime.seenNearbyPeds[ped] then
                    runtime.seenNearbyPeds[ped] = now
                    TriggerEvent('cbk_ai:onNPCSpawn', ped, distance)
                else
                    runtime.seenNearbyPeds[ped] = now
                end
            end
        end
    end

    for ped, lastSeen in pairs(runtime.seenNearbyPeds) do
        if not seenThisTick[ped] and (now - lastSeen) > 10000 then
            runtime.seenNearbyPeds[ped] = nil
        end
    end
end

local function getPlayerVehicleProtectionRetentionMs(config)
    local settings = (config and config.VehicleSettings) or {}
    return math.max(0, math.floor(tonumber(settings.playerVehicleProtectionMs) or 0))
end

local function updateProtectedPlayerVehicleState(config, playerPed)
    local runtime = CBKAI.RuntimeState
    local now = GetGameTimer()
    local currentVehicle = GetVehiclePedIsIn(playerPed, false)

    if currentVehicle ~= 0 and DoesEntityExist(currentVehicle) then
        local currentNetId = 0
        if NetworkGetEntityIsNetworked(currentVehicle) then
            currentNetId = NetworkGetNetworkIdFromEntity(currentVehicle)
        end

        runtime.currentPlayerVehicleHandle = currentVehicle
        runtime.currentPlayerVehicleNetId = currentNetId > 0 and currentNetId or 0
        runtime.lastPlayerVehicleHandle = currentVehicle
        if currentNetId > 0 then
            runtime.lastPlayerVehicleNetId = currentNetId
        end
        runtime.lastPlayerVehicleExitAt = 0
        return
    end

    if (runtime.currentPlayerVehicleHandle or 0) ~= 0 then
        runtime.lastPlayerVehicleHandle = runtime.currentPlayerVehicleHandle
        if (runtime.currentPlayerVehicleNetId or 0) > 0 then
            runtime.lastPlayerVehicleNetId = runtime.currentPlayerVehicleNetId
        end
        runtime.lastPlayerVehicleExitAt = now
    end

    runtime.currentPlayerVehicleHandle = 0
    runtime.currentPlayerVehicleNetId = 0

    if runtime.lastPlayerVehicleHandle ~= 0 and not DoesEntityExist(runtime.lastPlayerVehicleHandle) then
        runtime.lastPlayerVehicleHandle = 0
    end

    local retentionMs = getPlayerVehicleProtectionRetentionMs(config)
    if retentionMs <= 0 then
        runtime.lastPlayerVehicleNetId = 0
        runtime.lastPlayerVehicleHandle = 0
        runtime.lastPlayerVehicleExitAt = 0
        return
    end

    if (runtime.lastPlayerVehicleExitAt or 0) > 0 and (now - runtime.lastPlayerVehicleExitAt) > retentionMs then
        runtime.lastPlayerVehicleNetId = 0
        runtime.lastPlayerVehicleHandle = 0
        runtime.lastPlayerVehicleExitAt = 0
    end
end

local function buildProtectedVehicleNetIds(config)
    local runtime = CBKAI.RuntimeState
    local settings = (config and config.VehicleSettings) or {}
    local ids = {}
    local seen = {}

    local function push(netId)
        if netId > 0 and not seen[netId] then
            seen[netId] = true
            ids[#ids + 1] = netId
        end
    end

    push(runtime.currentPlayerVehicleNetId or 0)

    if settings.preservePlayerLastVehicle ~= false then
        local retentionMs = getPlayerVehicleProtectionRetentionMs(config)
        if (runtime.lastPlayerVehicleExitAt or 0) == 0 or (retentionMs > 0 and (GetGameTimer() - runtime.lastPlayerVehicleExitAt) <= retentionMs) then
            push(runtime.lastPlayerVehicleNetId or 0)
        end
    end

    return ids
end

local function buildProtectedVehicleLookup(netIds)
    local lookup = {}
    if type(netIds) ~= 'table' then
        return lookup
    end

    for i = 1, #netIds do
        local netId = math.floor(tonumber(netIds[i]) or 0)
        if netId > 0 then
            lookup[netId] = true
        end
    end

    return lookup
end

local function isLocalLastPlayerVehicleProtected(vehicle, config)
    local runtime = CBKAI.RuntimeState
    local settings = (config and config.VehicleSettings) or {}
    if settings.preservePlayerLastVehicle == false then
        return false
    end

    if vehicle == 0 or vehicle ~= (runtime.lastPlayerVehicleHandle or 0) then
        return false
    end

    local retentionMs = getPlayerVehicleProtectionRetentionMs(config)
    if retentionMs <= 0 then
        return false
    end

    local lastExitAt = runtime.lastPlayerVehicleExitAt or 0
    return lastExitAt == 0 or (GetGameTimer() - lastExitAt) <= retentionMs
end

local function trimAmbientOnFootPeds(config, playerCoords)
    local advanced = config.Advanced or {}
    local maxAmbientPeds = math.max(0, math.floor(tonumber(advanced.maxAmbientPeds) or 0))
    local maxDistance = advanced.maxNPCDistance or 500.0

    local ambientPeds = {}
    local peds = GetGamePool('CPed') or {}
    for i = 1, #peds do
        local ped = peds[i]
        if ped ~= 0
            and DoesEntityExist(ped)
            and not IsPedAPlayer(ped)
            and not IsPedInAnyVehicle(ped, false)
            and not IsPedDeadOrDying(ped, true)
            and #(GetEntityCoords(ped) - playerCoords) <= maxDistance
        then
            ambientPeds[#ambientPeds + 1] = ped
        end
    end

    if #ambientPeds <= maxAmbientPeds then
        return
    end

    table.sort(ambientPeds, function(a, b)
        return #(GetEntityCoords(a) - playerCoords) > #(GetEntityCoords(b) - playerCoords)
    end)

    for i = maxAmbientPeds + 1, #ambientPeds do
        deleteEntitySafely(ambientPeds[i])
    end
end

local function pruneEntityTracker(tracker)
    for entity, _ in pairs(tracker) do
        if entity == 0 or not DoesEntityExist(entity) then
            tracker[entity] = nil
        end
    end
end

local function clearAmbientWorld()
    local config = CBKAI.ClientState.config or Config
    updateProtectedPlayerVehicleState(config, PlayerPedId())
    local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local protectedLookup = buildProtectedVehicleLookup(CBKAI.ClientState.clearWorldProtectedVehicleNetIds)
    local localProtectedNetIds = buildProtectedVehicleNetIds(config)
    for i = 1, #localProtectedNetIds do
        protectedLookup[localProtectedNetIds[i]] = true
    end

    local peds = GetGamePool('CPed') or {}
    for i = 1, #peds do
        local ped = peds[i]
        if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            deleteEntitySafely(ped)
        end
    end

    local vehicles = GetGamePool('CVehicle') or {}
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        local keepVehicle = false
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            keepVehicle = vehicle == playerVehicle
                or isVehiclePlayerOccupied(vehicle)
                or isLocalLastPlayerVehicleProtected(vehicle, config)

            if not keepVehicle and NetworkGetEntityIsNetworked(vehicle) then
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                keepVehicle = netId > 0 and protectedLookup[netId] == true
            end
        end

        if vehicle ~= 0 and DoesEntityExist(vehicle) and not keepVehicle then
            deleteEntitySafely(vehicle)
        end
    end

    CBKAI.RuntimeState.seenNearbyPeds = {}
    CBKAI.RuntimeState.deadPedSeenAt = {}
    CBKAI.RuntimeState.wreckedVehicleSeenAt = {}
    CBKAI.RuntimeState.abandonedVehicleSeenAt = {}
    CBKAI.RuntimeState.lastPedTrimAt = 0
end

local function applyPedBehaviorToEntity(ped, playerPed, settings, accuracy, shootRate)
    local timeout = GetGameTimer() + 150
    while not NetworkHasControlOfEntity(ped) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(ped)
        Wait(0)
    end

    local playerCoords = GetEntityCoords(playerPed)
    local pedCoords = GetEntityCoords(ped)
    local distance = #(pedCoords - playerCoords)
    local blockShockingEvents = settings.ignorePlayer == true
        or settings.panicFromGunfire == false
        or settings.reactToExplosions == false
        or settings.reactToFire == false
        or settings.reactToDeadBodies == false
        or settings.reactToSirens == false

    local seeingRange = settings.ignorePlayer == true and 0.0 or (settings.pedSeeingRange or 100.0)
    local hearingRange = settings.ignorePlayer == true and 0.0 or (settings.pedHearingRange or 100.0)
    if settings.panicFromGunfire == false then
        hearingRange = 0.0
    end

    local alertness = settings.ignorePlayer == true and 0 or (settings.pedAlertness or 1)

    if settings.fleeFromPlayer and not IsPedInAnyVehicle(ped, false) then
        ClearPedTasks(ped)
        TaskReactAndFleePed(ped, playerPed)
        TaskSmartFleePed(ped, playerPed, 80.0, -1, false, false)
    end

    SetPedSeeingRange(ped, seeingRange)
    SetPedHearingRange(ped, hearingRange)
    SetPedAlertness(ped, alertness)

    if settings.disableNPCWeapons then
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        SetPedDropsWeaponsWhenDead(ped, false)
    end

    StopPedSpeaking(ped, settings.disableAmbientSpeech == true)
    DisablePedPainAudio(ped, settings.disablePainAudio == true)
    SetPedCanPlayAmbientAnims(ped, settings.disableAmbientAnims ~= true)
    SetPedCanPlayAmbientBaseAnims(ped, settings.disableAmbientBaseAnims ~= true)
    SetPedCanPlayGestureAnims(ped, settings.disableGestureAnims ~= true)
    SetBlockingOfNonTemporaryEvents(ped, blockShockingEvents)
    TaskSetBlockingOfNonTemporaryEvents(ped, blockShockingEvents)
    SetPedCanEvasiveDive(ped, settings.canEvasiveDive ~= false)
    SetPedCanCowerInCover(ped, settings.canCowerInCover ~= false)
    SetPedCanBeTargetted(ped, settings.canBeTargetted ~= false)
    SetPedCanBeTargettedByPlayer(ped, PlayerId(), settings.canBeTargettedByPlayer ~= false)
    SetPedCanBeShotInVehicle(ped, settings.canBeShotInVehicle ~= false)
    SetPedCanBeDraggedOut(ped, settings.canBeDraggedOutOfVehicle ~= false)
    SetPedPathCanUseLadders(ped, settings.canUseLadders ~= false)
    SetPedPathCanUseClimbovers(ped, settings.canUseClimbovers ~= false)
    SetPedPathCanDropFromHeight(ped, settings.canDropFromHeight ~= false)
    SetPedPathAvoidFire(ped, settings.pathAvoidFire ~= false)
    SetPedMoveRateOverride(ped, settings.moveRateOverride or 1.0)

    SetPedAccuracy(ped, accuracy)
    SetPedShootRate(ped, shootRate)

    if settings.disableNPCCombat then
        SetPedCombatAbility(ped, 0)
        SetPedCombatMovement(ped, 0)
        SetPedCanSwitchWeapon(ped, false)
        SetPedAsEnemy(ped, false)
        SetPedCombatAttributes(ped, 46, false)
        SetPedCombatAttributes(ped, 5, false)
    else
        SetPedCombatAbility(ped, settings.combatAbility or 1)
        SetPedCombatMovement(ped, settings.combatMovement or 1)
        SetPedCanSwitchWeapon(ped, true)
    end

    if settings.ignorePlayer == false and settings.fleeFromPlayer == false and distance <= 25.0 and not blockShockingEvents then
        SetBlockingOfNonTemporaryEvents(ped, false)
        TaskSetBlockingOfNonTemporaryEvents(ped, false)
    end

    SetPedCanRagdoll(ped, settings.npcCanRagdoll ~= false)
    SetPedCanRagdollFromPlayerImpact(ped, settings.allowPlayerMelee ~= false)
    SetPedCanBeKnockedOffVehicle(ped, settings.npcCanBeKnockedOffBike and 0 or 1)
end

local function applyVehicleBehaviorToDriver(driver, vehicle, settings, vehicleSettings)
    local vehicleTimeout = GetGameTimer() + 150
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < vehicleTimeout do
        NetworkRequestControlOfEntity(vehicle)
        Wait(0)
    end

    local driverTimeout = GetGameTimer() + 150
    while not NetworkHasControlOfEntity(driver) and GetGameTimer() < driverTimeout do
        NetworkRequestControlOfEntity(driver)
        Wait(0)
    end

    if settings.disableNPCDriving then
        TaskVehicleTempAction(driver, vehicle, 27, 1500)
        SetVehicleForwardSpeed(vehicle, 0.0)
        SetVehicleBrakeLights(vehicle, true)
        return
    end

    local style = settings.npcDrivingStyle or 'normal'
    local driverAbility = 0.75
    local driverAggressiveness = settings.avoidTraffic == false and 0.75 or 0.25

    if style == 'careful' then
        driverAbility = 1.0
        driverAggressiveness = 0.0
    elseif style == 'reckless' then
        driverAbility = 0.25
        driverAggressiveness = 1.0
    elseif style == 'ignored' then
        driverAbility = 0.5
        driverAggressiveness = 0.5
    end

    if vehicleSettings.vehiclesRespectLights ~= false and settings.respectTrafficLights ~= false then
        if style == 'reckless' then
            driverAbility = math.max(driverAbility, 0.65)
            driverAggressiveness = math.min(driverAggressiveness, 0.65)
        elseif style == 'ignored' then
            driverAbility = math.max(driverAbility, 0.7)
            driverAggressiveness = math.min(driverAggressiveness, 0.45)
        else
            driverAbility = math.max(driverAbility, 0.85)
            driverAggressiveness = math.min(driverAggressiveness, 0.25)
        end
    end

    SetDriverAbility(driver, driverAbility)
    SetDriverAggressiveness(driver, driverAggressiveness)

    if vehicleSettings.vehiclesUseIndicators == false then
        SetVehicleIndicatorLights(vehicle, 0, false)
        SetVehicleIndicatorLights(vehicle, 1, false)
    end
end

local buildRuntimeReport

local function runAdvancedMaintenance(config, playerCoords)
    local advanced = config.Advanced or {}
    local runtime = CBKAI.RuntimeState
    local now = GetGameTimer()
    local cleanupInterval = advanced.cleanupInterval or 60000
    local pedTrimInterval = math.max(2000, math.min(10000, ((advanced.updateInterval or 1000) * 2)))

    if now - (runtime.lastPedTrimAt or 0) >= pedTrimInterval then
        runtime.lastPedTrimAt = now
        trimAmbientOnFootPeds(config, playerCoords)
    end

    if now - (runtime.lastCleanupAt or 0) >= cleanupInterval then
        runtime.lastCleanupAt = now
        local cleanupDistance = advanced.cleanupDistance or 1000.0
        local deadPedSeenAt = runtime.deadPedSeenAt or {}
        local wreckedVehicleSeenAt = runtime.wreckedVehicleSeenAt or {}
        local abandonedVehicleSeenAt = runtime.abandonedVehicleSeenAt or {}
        runtime.deadPedSeenAt = deadPedSeenAt
        runtime.wreckedVehicleSeenAt = wreckedVehicleSeenAt
        runtime.abandonedVehicleSeenAt = abandonedVehicleSeenAt

        pruneEntityTracker(deadPedSeenAt)
        pruneEntityTracker(wreckedVehicleSeenAt)
        pruneEntityTracker(abandonedVehicleSeenAt)

        local peds = GetGamePool('CPed') or {}
        for i = 1, #peds do
            local ped = peds[i]
            if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                if advanced.autoCleanupEnabled and #(GetEntityCoords(ped) - playerCoords) > cleanupDistance then
                    deleteEntitySafely(ped)
                elseif advanced.deleteDeadNPCs then
                    if IsPedDeadOrDying(ped, true) then
                        local firstSeenAt = deadPedSeenAt[ped] or now
                        deadPedSeenAt[ped] = firstSeenAt
                        if (advanced.cleanupDeadNPCsAfterMs or 0) <= 0 or (now - firstSeenAt) >= (advanced.cleanupDeadNPCsAfterMs or 15000) then
                            deleteEntitySafely(ped)
                            deadPedSeenAt[ped] = nil
                        end
                    else
                        deadPedSeenAt[ped] = nil
                    end
                else
                    deadPedSeenAt[ped] = nil
                end
            end
        end

        local vehicles = GetGamePool('CVehicle') or {}
        for i = 1, #vehicles do
            local vehicle = vehicles[i]
            if vehicle ~= 0 and DoesEntityExist(vehicle) and not isVehiclePlayerOccupied(vehicle) and not isLocalLastPlayerVehicleProtected(vehicle, config) then
                local driver = GetPedInVehicleSeat(vehicle, -1)
                if driver == 0 or not IsPedAPlayer(driver) then
                    if advanced.autoCleanupEnabled and #(GetEntityCoords(vehicle) - playerCoords) > cleanupDistance then
                        deleteEntitySafely(vehicle)
                    else
                        local vehicleDeleted = false
                        local vehicleIsEmpty = not isVehicleOccupiedByAnyPed(vehicle)
                        local vehicleIsWrecked = vehicleIsEmpty and (
                            IsEntityDead(vehicle)
                            or GetVehicleEngineHealth(vehicle) <= 0.0
                            or GetVehicleBodyHealth(vehicle) <= 0.0
                        )

                        if advanced.deleteWreckedEmptyVehicles and vehicleIsWrecked then
                            local firstSeenAt = wreckedVehicleSeenAt[vehicle] or now
                            wreckedVehicleSeenAt[vehicle] = firstSeenAt
                            if (advanced.cleanupWreckedVehiclesAfterMs or 0) <= 0 or (now - firstSeenAt) >= (advanced.cleanupWreckedVehiclesAfterMs or 45000) then
                                deleteEntitySafely(vehicle)
                                wreckedVehicleSeenAt[vehicle] = nil
                                vehicleDeleted = true
                            end
                        else
                            wreckedVehicleSeenAt[vehicle] = nil
                        end

                        local speedThreshold = (advanced.abandonedVehicleSpeedThresholdMph or 1.0) * 0.44704
                        local vehicleIsAbandoned = (not vehicleDeleted) and vehicleIsEmpty and not vehicleIsWrecked and GetEntitySpeed(vehicle) <= speedThreshold
                        if advanced.deleteAbandonedEmptyVehicles and vehicleIsAbandoned then
                            local firstSeenAt = abandonedVehicleSeenAt[vehicle] or now
                            abandonedVehicleSeenAt[vehicle] = firstSeenAt
                            if (advanced.cleanupAbandonedVehiclesAfterMs or 0) <= 0 or (now - firstSeenAt) >= (advanced.cleanupAbandonedVehiclesAfterMs or 300000) then
                                deleteEntitySafely(vehicle)
                                abandonedVehicleSeenAt[vehicle] = nil
                            end
                        else
                            abandonedVehicleSeenAt[vehicle] = nil
                        end
                    end
                end
            end
        end
    end

    if (advanced.debug or advanced.showNPCCount) and now - (runtime.lastDebugAt or 0) >= 10000 then
        runtime.lastDebugAt = now
        local report = buildRuntimeReport(playerCoords, advanced.maxNPCDistance or 500.0)
        print(('[CBK AI] nearby ambient peds=%d vehicles=%d | rev=%d'):format(
            report.nearbyAmbientPeds,
            report.nearbyAmbientVehicles,
            report.revision
        ))
    end
end

buildRuntimeReport = function(playerCoords, maxDistance)
    updateProtectedPlayerVehicleState(CBKAI.ClientState.config or Config, PlayerPedId())

    local report = {
        nearbyAmbientPeds = 0,
        nearbyAmbientVehicles = 0,
        nearbyManagedPeds = 0,
        nearbyManagedVehicles = 0,
        standaloneAmbientControl = CBKAI.ClientState.config.Advanced == nil or CBKAI.ClientState.config.Advanced.standaloneAmbientControl ~= false,
        revision = CBKAI.ClientState.revision or 0,
        protectedVehicleNetIds = buildProtectedVehicleNetIds(CBKAI.ClientState.config or Config),
    }

    local peds = GetGamePool('CPed') or {}
    for i = 1, #peds do
        local ped = peds[i]
        if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) and #(GetEntityCoords(ped) - playerCoords) <= maxDistance then
            report.nearbyAmbientPeds = report.nearbyAmbientPeds + 1
        end
    end

    local vehicles = GetGamePool('CVehicle') or {}
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if vehicle ~= 0 and DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - playerCoords) <= maxDistance then
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver ~= 0 and not IsPedAPlayer(driver) then
                report.nearbyAmbientVehicles = report.nearbyAmbientVehicles + 1
            end
        end
    end

    return report
end

local function applyAmbientNpcBehavior()
    local config = CBKAI.ClientState.config
    local settings = config.NPCBehavior
    local vehicleSettings = config.VehicleSettings or {}
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local maxDistance = (config.Advanced and config.Advanced.maxNPCDistance) or 500.0
    local pedRules = getPedModelRules(config)
    local spawnControl = config.SpawnControl or {}
    local ambientPedSuppression = spawnControl.enabled and spawnControl.disableAmbientPeds == true
    local clearWorldUntil = CBKAI.ClientState.clearWorldUntil or 0

    updateProtectedPlayerVehicleState(config, playerPed)

    if not config.EnableNPCs then
        SetEveryoneIgnorePlayer(PlayerId(), false)
        SetPoliceIgnorePlayer(PlayerId(), false)
        return
    end

    local ignorePlayer = settings.ignorePlayer == true
    SetEveryoneIgnorePlayer(PlayerId(), ignorePlayer)
    SetPoliceIgnorePlayer(PlayerId(), ignorePlayer)
    applyRelationshipSettings(config)
    emitRuntimeEvents(config, playerPed, playerCoords)

    local accuracy = math.floor(clamp((settings.npcAccuracy or 0.1) * 100.0, 0.0, 100.0))
    local shootRate = math.floor(clamp(settings.npcShootRate or 100, 1, 1000))

    if clearWorldUntil ~= 0 and clearWorldUntil <= GetGameTimer() and CBKAI.ClientState.clearWorldProtectedVehicleNetIds ~= nil then
        CBKAI.ClientState.clearWorldProtectedVehicleNetIds = nil
    end

    if clearWorldUntil > GetGameTimer() then
        clearAmbientWorld()
        return
    end

    if config.Advanced == nil or config.Advanced.standaloneAmbientControl ~= false then
        local ambientPeds = GetGamePool('CPed') or {}
        for i = 1, #ambientPeds do
            local ped = ambientPeds[i]
            if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                local coords = GetEntityCoords(ped)
                if #(coords - playerCoords) <= maxDistance then
                    local modelHash = GetEntityModel(ped)
                    if ambientPedSuppression then
                        deleteEntitySafely(ped)
                    elseif not isPedModelAllowed(modelHash, pedRules) or isAnimalModel(modelHash, config) then
                        deleteEntitySafely(ped)
                    else
                        applyPedBehaviorToEntity(ped, playerPed, settings, accuracy, shootRate)
                    end
                end
            end
        end

        local ambientVehicles = GetGamePool('CVehicle') or {}
        for i = 1, #ambientVehicles do
            local vehicle = ambientVehicles[i]
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                local coords = GetEntityCoords(vehicle)
                if #(coords - playerCoords) <= maxDistance then
                    if config.SpawnControl and config.SpawnControl.enabled and config.SpawnControl.disableVehicleSpawn then
                        if not isVehiclePlayerOccupied(vehicle) and not isLocalLastPlayerVehicleProtected(vehicle, config) then
                            deleteEntitySafely(vehicle)
                        end
                    else
                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        if driver ~= 0 and not IsPedAPlayer(driver) then
                            applyPedBehaviorToEntity(driver, playerPed, settings, accuracy, shootRate)
                            applyVehicleBehaviorToDriver(driver, vehicle, settings, vehicleSettings)
                        end
                    end
                end
            end
        end
    end

    if GetGameTimer() - (CBKAI.RuntimeState.lastReportAt or 0) >= 5000 then
        CBKAI.RuntimeState.lastReportAt = GetGameTimer()
        TriggerServerEvent('cbk_ai:sv:runtimeReport', buildRuntimeReport(playerCoords, maxDistance))
    end

    runAdvancedMaintenance(config, playerCoords)
end

RegisterNetEvent('cbk_ai:cl:clearWorld', function(payload)
    local protectedVehicleNetIds = {}
    if type(payload) == 'table' then
        protectedVehicleNetIds = payload.protectedVehicleNetIds
    end

    CBKAI.ClientState.clearWorldProtectedVehicleNetIds = buildProtectedVehicleLookup(protectedVehicleNetIds)
    CBKAI.ClientState.clearWorldUntil = GetGameTimer() + 5000
    clearAmbientWorld()
    TriggerEvent('cbk_ai:localWorldCleared')
end)

local function applyConfigPatch(base, patch)
    for i = 1, #patch.ops do
        local op = patch.ops[i]
        local node = base

        for p = 1, (#op.path - 1) do
            local key = op.path[p]
            if node[key] == nil or type(node[key]) ~= 'table' then
                node[key] = {}
            end
            node = node[key]
        end

        local finalKey = op.path[#op.path]
        if op.remove then
            node[finalKey] = nil
        else
            node[finalKey] = op.value
        end
    end
end

RegisterNetEvent('cbk_ai:cl:syncFull', function(payload)
    if type(payload) ~= 'table' or type(payload.config) ~= 'table' or type(payload.revision) ~= 'number' then
        return
    end

    CBKAI.ClientState.config = deepClone(payload.config)
    CBKAI.ClientState.revision = payload.revision
end)

RegisterNetEvent('cbk_ai:cl:syncPatch', function(payload)
    if type(payload) ~= 'table' or type(payload.revision) ~= 'number' or type(payload.ops) ~= 'table' then
        return
    end

    if payload.revision <= (CBKAI.ClientState.revision or 0) then
        return
    end

    applyConfigPatch(CBKAI.ClientState.config, payload)
    CBKAI.ClientState.revision = payload.revision
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('cbk_ai:sv:requestInit')

    while true do
        applyAmbientNpcBehavior()
        Wait(CBKAI.ClientState.config.Advanced.updateInterval or 1000)
    end
end)

RegisterNetEvent('ai_controller:showNPCCount', function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local maxDistance = (CBKAI.ClientState.config.Advanced and CBKAI.ClientState.config.Advanced.maxNPCDistance) or 500.0
    local report = buildRuntimeReport(playerCoords, maxDistance)

    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 255 },
        multiline = true,
        args = { 'AI Controller', ('Nearby ambient: peds=%d vehicles=%d'):format(report.nearbyAmbientPeds, report.nearbyAmbientVehicles) }
    })
end)
