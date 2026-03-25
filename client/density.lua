CBKAI = CBKAI or {}

CBKAI.ClientState = CBKAI.ClientState or {
    config = Config,
    revision = 0,
}

local scenarioTypeMap = {
    cops = {
        'WORLD_HUMAN_COP_IDLES',
        'WORLD_VEHICLE_POLICE_BIKE',
        'WORLD_VEHICLE_POLICE_CAR',
        'WORLD_VEHICLE_POLICE_NEXT_TO_CAR',
        'WORLD_VEHICLE_SECURITY_CAR',
    },
    paramedics = {
        'CODE_HUMAN_MEDIC_TEND_TO_DEAD',
        'CODE_HUMAN_MEDIC_TIME_OF_DEATH',
        'WORLD_VEHICLE_AMBULANCE',
    },
    firemen = {
        'WORLD_HUMAN_STAND_FIRE',
        'WORLD_HUMAN_FIRE_EXTINGUISH',
        'WORLD_VEHICLE_FIRE_TRUCK',
    },
    vendors = {
        'WORLD_HUMAN_AA_COFFEE',
        'WORLD_HUMAN_DRINKING',
        'WORLD_HUMAN_SMOKING',
        'WORLD_HUMAN_STAND_IMPATIENT',
        'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT',
    },
    beggars = {
        'WORLD_HUMAN_BUM_FREEWAY',
        'WORLD_HUMAN_BUM_SLUMPED',
        'WORLD_HUMAN_BUM_STANDING',
        'WORLD_HUMAN_BUM_WASH',
    },
    buskers = {
        'WORLD_HUMAN_MUSICIAN',
    },
    hookers = {
        'WORLD_VEHICLE_PROSTITUTE_HIGH_CLASS',
        'WORLD_VEHICLE_PROSTITUTE_LOW_CLASS',
    },
    dealer = {
        'PROP_HUMAN_SEAT_DEALER',
        'WORLD_HUMAN_DRUG_DEALER',
    },
    crime = {
        'WORLD_HUMAN_GUARD_PATROL',
        'WORLD_HUMAN_GUARD_STAND',
    },
}

CBKAI.ClientScenarioTypes = scenarioTypeMap

local function setScenarioTypesEnabled(types, enabled)
    for i = 1, #types do
        SetScenarioTypeEnabled(types[i], enabled)
    end
end

local lastScenarioSuppressionKey = nil

local function resetScenarioSuppression()
    if lastScenarioSuppressionKey == nil then
        return
    end

    for _, types in pairs(scenarioTypeMap) do
        setScenarioTypesEnabled(types, true)
    end

    lastScenarioSuppressionKey = nil
end

local function applyScenarioSuppression(config)
    local settings = config.ScenarioSettings or {}
    local disableAll = settings.disableAllScenarios == true
    local suppressionKey = table.concat({
        tostring(disableAll),
        tostring(settings.disableCops == true),
        tostring(settings.disableParamedics == true),
        tostring(settings.disableFiremen == true),
        tostring(settings.disableVendors == true),
        tostring(settings.disableBeggars == true),
        tostring(settings.disableBuskers == true),
        tostring(settings.disableHookers == true),
        tostring(settings.disableDealer == true),
        tostring(settings.disableCrimeScenarios == true),
    }, '|')

    if suppressionKey == lastScenarioSuppressionKey then
        return
    end

    setScenarioTypesEnabled(scenarioTypeMap.cops, not (disableAll or settings.disableCops))
    setScenarioTypesEnabled(scenarioTypeMap.paramedics, not (disableAll or settings.disableParamedics))
    setScenarioTypesEnabled(scenarioTypeMap.firemen, not (disableAll or settings.disableFiremen))
    setScenarioTypesEnabled(scenarioTypeMap.vendors, not (disableAll or settings.disableVendors))
    setScenarioTypesEnabled(scenarioTypeMap.beggars, not (disableAll or settings.disableBeggars))
    setScenarioTypesEnabled(scenarioTypeMap.buskers, not (disableAll or settings.disableBuskers))
    setScenarioTypesEnabled(scenarioTypeMap.hookers, not (disableAll or settings.disableHookers))
    setScenarioTypesEnabled(scenarioTypeMap.dealer, not (disableAll or settings.disableDealer))
    setScenarioTypesEnabled(scenarioTypeMap.crime, not (disableAll or settings.disableCrimeScenarios))

    lastScenarioSuppressionKey = suppressionKey
end

local function isExplicitDensityFactor(value)
    return type(value) == 'number' and value >= 0.0 and value < 0.999
end

local function clampDensityFactor(value)
    value = tonumber(value)
    if value == nil then
        return nil
    end

    return math.max(0.0, math.min(1.0, value))
end

local function isStandaloneAmbientControlEnabled(config)
    config = config or {}
    local advanced = config.Advanced or {}
    return advanced.standaloneAmbientControl ~= false
end

local function getActiveTimeProfile(config)
    local timeBased = config.TimeBasedSettings or {}
    local hour = GetClockHours()
    local daytime = hour >= 6 and hour < 18
    return daytime and (timeBased.daySettings or {}) or (timeBased.nightSettings or {})
end

local function getEffectivePedDensityFactor(config)
    if not isStandaloneAmbientControlEnabled(config) then
        return 1.0
    end

    local spawnControl = config.SpawnControl or {}
    if spawnControl.enabled and spawnControl.disableAmbientPeds == true then
        return 0.0
    end

    local timeBased = config.TimeBasedSettings or {}
    if timeBased.enabled then
        return tonumber((getActiveTimeProfile(config) or {}).pedDensity) or 1.0
    end

    local population = config.PopulationDensity or {}
    if population.enabled then
        return tonumber(population.pedDensity) or 1.0
    end

    return 1.0
end

local function getEffectiveVehicleDensityFactor(config)
    if not isStandaloneAmbientControlEnabled(config) then
        return 1.0
    end

    local spawnControl = config.SpawnControl or {}
    if spawnControl.enabled and spawnControl.disableVehicleSpawn == true then
        return 0.0
    end

    local vehicleSettings = config.VehicleSettings or {}
    if vehicleSettings.enableTraffic == false then
        return 0.0
    end

    local timeBased = config.TimeBasedSettings or {}
    if timeBased.enabled then
        return tonumber((getActiveTimeProfile(config) or {}).vehicleDensity) or 1.0
    end

    local population = config.PopulationDensity or {}
    if population.enabled then
        return tonumber(population.vehicleDensity) or 1.0
    end

    return 1.0
end

CBKAI.ClientDensity = CBKAI.ClientDensity or {}
CBKAI.ClientDensity.GetEffectivePedDensityFactor = getEffectivePedDensityFactor
CBKAI.ClientDensity.GetEffectiveVehicleDensityFactor = getEffectiveVehicleDensityFactor

local function applyDensity(config)
    config = config or {}

    local clearWorldUntil = CBKAI.ClientState.clearWorldUntil or 0
    if clearWorldUntil > GetGameTimer() then
        SetPedDensityMultiplierThisFrame(0.0)
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
        return
    end

    if not config.EnableNPCs or not isStandaloneAmbientControlEnabled(config) then
        resetScenarioSuppression()
        return
    end

    local population = config.PopulationDensity or {}
    local pedDensity = nil
    local scenarioPedDensity = nil
    local vehicleDensity = nil
    local parkedVehicleDensity = nil

    if population.enabled then
        pedDensity = clampDensityFactor(population.pedDensity)
        scenarioPedDensity = clampDensityFactor(population.scenarioPedDensity)
        vehicleDensity = clampDensityFactor(population.vehicleDensity)
        parkedVehicleDensity = clampDensityFactor(population.parkedVehicleDensity)
    end

    local timeBased = config.TimeBasedSettings or {}
    if timeBased.enabled then
        local selected = getActiveTimeProfile(config)
        pedDensity = clampDensityFactor(selected.pedDensity)
        vehicleDensity = clampDensityFactor(selected.vehicleDensity)

        if selected.enableScenarios == false then
            scenarioPedDensity = 0.0
        end
    end

    local spawnControl = config.SpawnControl or {}
    if spawnControl.enabled then
        if spawnControl.disableAmbientPeds == true then
            pedDensity = 0.0
        end

        if spawnControl.disableVehicleSpawn == true then
            vehicleDensity = 0.0
        end

        if spawnControl.disableParkedVehicles == true then
            parkedVehicleDensity = 0.0
        end

        if spawnControl.disableScenarioPeds == true then
            scenarioPedDensity = 0.0
        end
    end

    if config.ScenarioSettings and config.ScenarioSettings.disableAllScenarios then
        scenarioPedDensity = 0.0
    end

    if config.VehicleSettings then
        if config.VehicleSettings.enableTraffic == false then
            vehicleDensity = 0.0
        end
    end

    if isExplicitDensityFactor(pedDensity) then
        SetPedDensityMultiplierThisFrame(pedDensity)
    end

    if isExplicitDensityFactor(scenarioPedDensity) then
        SetScenarioPedDensityMultiplierThisFrame(scenarioPedDensity, scenarioPedDensity)
    end

    if isExplicitDensityFactor(vehicleDensity) then
        SetVehicleDensityMultiplierThisFrame(vehicleDensity)
        SetRandomVehicleDensityMultiplierThisFrame(vehicleDensity)
    end

    if isExplicitDensityFactor(parkedVehicleDensity) then
        SetParkedVehicleDensityMultiplierThisFrame(parkedVehicleDensity)
    end

    applyScenarioSuppression(config)
end

CreateThread(function()
    while true do
        Wait(0)
        applyDensity(CBKAI.ClientState.config)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    resetScenarioSuppression()
end)
