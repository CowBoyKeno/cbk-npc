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
        'WORLD_HUMAN_DRUG_DEALER',
        'WORLD_HUMAN_GUARD_PATROL',
        'WORLD_HUMAN_GUARD_STAND',
    },
}

local function setScenarioTypesEnabled(types, enabled)
    for i = 1, #types do
        SetScenarioTypeEnabled(types[i], enabled)
    end
end

local function applyScenarioSuppression(config)
    local settings = config.ScenarioSettings or {}
    local disableAll = settings.disableAllScenarios == true

    setScenarioTypesEnabled(scenarioTypeMap.cops, not (disableAll or settings.disableCops))
    setScenarioTypesEnabled(scenarioTypeMap.paramedics, not (disableAll or settings.disableParamedics))
    setScenarioTypesEnabled(scenarioTypeMap.firemen, not (disableAll or settings.disableFiremen))
    setScenarioTypesEnabled(scenarioTypeMap.vendors, not (disableAll or settings.disableVendors))
    setScenarioTypesEnabled(scenarioTypeMap.beggars, not (disableAll or settings.disableBeggars))
    setScenarioTypesEnabled(scenarioTypeMap.buskers, not (disableAll or settings.disableBuskers))
    setScenarioTypesEnabled(scenarioTypeMap.hookers, not (disableAll or settings.disableHookers))
    setScenarioTypesEnabled(scenarioTypeMap.dealer, not (disableAll or settings.disableDealer))
    setScenarioTypesEnabled(scenarioTypeMap.crime, not (disableAll or settings.disableCrimeScenarios))
end

local function applyFinalHardSuppression(config)
    local spawnControl = config.SpawnControl or {}
    if spawnControl.enabled ~= true then
        return
    end

    local suppressPeds = spawnControl.disableAmbientPeds == true

    if suppressPeds then
        SetPedDensityMultiplierThisFrame(0.0)
    end

    if spawnControl.disableVehicleSpawn == true then
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
    end

    if spawnControl.disableParkedVehicles == true then
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
    end

    if spawnControl.disableScenarioPeds == true then
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
    end
end

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

    if not config.EnableNPCs then
        SetPedDensityMultiplierThisFrame(0.0)
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
        return
    end

    local population = config.PopulationDensity or {}
    if population.enabled then
        SetPedDensityMultiplierThisFrame(population.pedDensity or 0.0)
        SetScenarioPedDensityMultiplierThisFrame(population.scenarioPedDensity or 0.0, population.scenarioPedDensity or 0.0)
        SetVehicleDensityMultiplierThisFrame(population.vehicleDensity or 0.0)
        SetRandomVehicleDensityMultiplierThisFrame(population.vehicleDensity or 0.0)
        SetParkedVehicleDensityMultiplierThisFrame(population.parkedVehicleDensity or 0.0)
    end

    local spawnControl = config.SpawnControl or {}
    if spawnControl.enabled then
        local suppressPeds = spawnControl.disableAmbientPeds == true

        if suppressPeds then
            SetPedDensityMultiplierThisFrame(0.0)
        end

        if spawnControl.disableVehicleSpawn then
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
        end

        if spawnControl.disableParkedVehicles then
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
        end

        if spawnControl.disableScenarioPeds then
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        end
    end

    if config.ScenarioSettings and config.ScenarioSettings.disableAllScenarios then
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
    end

    local timeBased = config.TimeBasedSettings or {}
    if timeBased.enabled then
        local hour = GetClockHours()
        local daytime = hour >= 6 and hour < 18
        local selected = daytime and (timeBased.daySettings or {}) or (timeBased.nightSettings or {})

        SetPedDensityMultiplierThisFrame(selected.pedDensity or 0.0)
        SetVehicleDensityMultiplierThisFrame(selected.vehicleDensity or 0.0)

        if not selected.enableScenarios then
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        end
    end

    if config.VehicleSettings then
        if config.VehicleSettings.enableTraffic == false then
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
        elseif config.VehicleSettings.trafficDensityOverridePopulation == true and type(config.VehicleSettings.trafficDensity) == 'number' then
            SetVehicleDensityMultiplierThisFrame(config.VehicleSettings.trafficDensity)
            SetRandomVehicleDensityMultiplierThisFrame(config.VehicleSettings.trafficDensity)
        end
    end

    applyScenarioSuppression(config)
    applyFinalHardSuppression(config)
end

CreateThread(function()
    while true do
        Wait(0)
        applyDensity(CBKAI.ClientState.config)
    end
end)
